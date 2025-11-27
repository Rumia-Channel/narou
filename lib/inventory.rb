# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "yaml"
require "ostruct"
require "monitor"
require_relative "narou"

#
# Narou.rbのシステムが記録するデータ単位
#
# .narou ディレクトリにYAMLファイルとして保存される
# scope に :global を指定するとユーザーディレクトリ/.narousetting に保存される
#
module Inventory
  def self.load(name = "local_setting", scope = :local)
    @@cache ||= {}
    return @@cache[name] if @@cache[name]
    
    # キャッシュサイズ制限（メモリリーク対策）
    # 重要な設定ファイルは保護、一時的なもののみ削除
    if @@cache.size > 200  # 上限を大幅に引き上げ
      protected_keys = ["local_setting", "database", "global_setting", "latest_convert"]
      removable_keys = @@cache.keys - protected_keys
      
      if removable_keys.any?
        # 保護対象外の最も古いエントリを削除
        oldest_removable = removable_keys.first
        @@cache.delete(oldest_removable)
      end
    end
    
    {}.tap { |h|
      h.extend(Inventory)
      h.init(name, scope)
      @@cache[name] = h
    }
  end

  def self.clear
    @@cache = {}
  end

  def init(name, scope)
    dir = case scope
          when :local
            Narou.local_setting_dir
          when :global
            Narou.global_setting_dir
          else
            raise "Unknown scope"
          end
    return nil unless dir
    @mutex = Monitor.new
    @inventory_file_path = File.join(dir, name + ".yaml")
    return unless File.exist?(@inventory_file_path)

    # キャッシュサイズが大きくなるファイルは CacheLoader を通さずに直接ロードする
    # CacheLoader は結果をメモリに保持し続けるため、これらの巨大なファイルがキャッシュされると
    # メモリリークの原因となる。
    # また、Inventory は読み込んだハッシュを直接変更するため、CacheLoader が保持するハッシュも
    # 更新されてしまい、GC対象にならなくなる。
    if ["section_convert_cache", "section_hash_cache", "database"].include?(name)
      yaml = File.read(@inventory_file_path, mode: "r:BOM|UTF-8")
      begin
        self.merge!(YAML.unsafe_load(yaml))
      rescue Psych::SyntaxError
        unless restore(@inventory_file_path)
          error "#{@inventory_file_path} が壊れてるっぽい"
          raise
        end
        begin
          self.merge!(YAML.unsafe_load_file(@inventory_file_path))
        rescue SystemCallError
          self.merge!(YAML.unsafe_load(File.read(@inventory_file_path)))
        end
      end
      return
    end

    self.merge!(Helper::CacheLoader.memo(@inventory_file_path) { |yaml|
      begin
        YAML.unsafe_load(yaml)
      rescue Psych::SyntaxError
        unless restore(@inventory_file_path)
          error "#{@inventory_file_path} が壊れてるっぽい"
          raise
        end
        begin
          YAML.unsafe_load_file(@inventory_file_path)
        rescue SystemCallError
          # bootsnap on Windows can raise Errno::E01 errors, fallback to standard YAML
          YAML.unsafe_load(File.read(@inventory_file_path))
        end
      end
    })
  end

  def save
    unless @inventory_file_path
      raise "not initialized setting dir yet"
    end
    @mutex.synchronize do
      atomic_write(@inventory_file_path, YAML.dump(self))
    end
  end

  private

  def atomic_write(file_path, content)
    temp_file_path = "#{file_path}.#{Process.pid}.#{rand(100000)}.tmp"
    File.write(temp_file_path, content)

    # Windowsでのファイルロック対策のためのリトライループ
    # ウイルス対策ソフトやインデックスサービスが一時的にロックする場合があるため
    20.times do |i|
      begin
        File.rename(temp_file_path, file_path)
        return
      rescue Errno::EACCES, Errno::EEXIST, Errno::EBUSY
        # ロックされている場合は少し待ってリトライ
        sleep 0.1 + (i * 0.05)
      end
    end
    
    # 最後に一度だけリトライなしで実行（エラーを発生させるため）
    File.rename(temp_file_path, file_path)
  ensure
    # テンポラリファイルが残っていたら削除
    if File.exist?(temp_file_path)
      begin
        File.delete(temp_file_path)
      rescue Errno::EACCES, Errno::EBUSY
        # 削除に失敗しても無視（次回の掃除などで消えることを期待）
      end
    end
  end

  public

  def synchronize
    @mutex.synchronize do
      yield self
    end
  end

  def restore(path)
    backup_path = "#{path}.backup"
    return nil unless File.exist?(backup_path)
    FileUtils.copy(backup_path, path)
    true
  end

  def group(group_name)
    result = {}
    each do |name, value|
      next unless name =~ /^#{group_name}\.(.+)$/
      child_name = $1
      result[child_name] = value
      lodashed_name = child_name.tr("-", "_")
      result[lodashed_name] = value if child_name != lodashed_name
    end
    OpenStruct.new(result)
  end
end
