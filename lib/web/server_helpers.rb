# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

# rubocop:disable Style/ClassAndModuleChildren

module Narou::ServerHelpers
  RELOAD_TIMING_DEFAULT = "every"
  SORT_COLUMN_KEYS = ["id", "last_update", "general_lastup", "last_check_date", "title", "author", "sitename", "novel_type", "tags", "general_all_no", "length", "status", "toc_url"].freeze
  SORT_COLUMN_LABELS = ["ID", "最終更新日", "最新話掲載日", "最終確認日", "タイトル", "作者", "サイト名", "小説種別", "タグ", "話数", "文字数", "状態", "URL"].freeze

  #
  # タグをHTMLで装飾する
  #
  def decorate_tags(tags)
    tag_command = Command.load_command("tag")
    tags.sort.map do |tag|
      %!<span class="tag label label-#{tag_command.get_color(tag)}" data-tag="#{escape_html(tag)}">#{escape_html(tag)}</span>!
    end.join(" ")
  end

  #
  # タグをHTMLで装飾する(除外タグ指定用)
  #
  def decorate_exclusion_tags(tags)
    tag_command = Command.load_command("tag")
    tags.sort.map do |tag|
      %!<span class="tag label label-#{tag_command.get_color(tag)}" data-exclusion-tag="#{escape_html(tag)}">^tag:#{escape_html(tag)}</span>!
    end.join(" ")
  end

  #
  # Rubyバージョンを構築
  #
  def build_ruby_version
    begin
      `"#{RbConfig.ruby}" -v`.strip
    rescue
      config = RbConfig::CONFIG
      "ruby #{RUBY_VERSION}p#{config["PATCHLEVEL"]} [#{RUBY_PLATFORM}]"
    end
  end

  #
  # 有効な novel ID だけの配列を生成する
  # ID が指定されなかったか、１件も存在しない場合は nil を返す
  #
  def select_valid_novel_ids(ids)
    return nil unless ids.kind_of?(Array)
    result = ids.select do |id|
      # 数値または数値文字列をチェック
      case id
      when Integer
        true
      when String
        id =~ /^\d+$/
      else
        false
      end
    end.map(&:to_s)  # 最終的に文字列に統一
    result.empty? ? nil : result
  end

  #
  # 現在のソート状態に基づいてIDを並び替える
  #
  def sort_ids_by_current_sort(ids)
    debug_puts "[DEBUG] sort_ids_by_current_sort called with #{ids ? ids.length : 0} IDs: #{ids.inspect}"
    return ids unless ids && ids.length > 0

    server_setting = Inventory.load("server_setting", :global)
    current_sort = server_setting["current_sort"]
    debug_puts "[DEBUG] Current sort from server: #{current_sort.inspect}"
    normalized_sort = normalize_sort_state(current_sort)
    debug_puts "[DEBUG] Normalized current sort: #{normalized_sort.inspect}"
    sorted_ids = sort_ids_with_state(ids, normalized_sort)
    debug_puts "[DEBUG] Sorted IDs: #{sorted_ids.inspect}"
    sorted_ids
  end

  #
  # 固定されたソート状態に基づいてIDを並び替える（convert実行時点のソート状態を保持）
  #
  def sort_ids_with_fixed_state(ids, sort_state)
    debug_puts "[DEBUG] sort_ids_with_fixed_state called with #{ids ? ids.length : 0} IDs"
    debug_puts "[DEBUG] Fixed sort state: #{sort_state.inspect}"
    return ids unless ids && ids.length > 0
    normalized_sort = normalize_sort_state(sort_state)
    debug_puts "[DEBUG] Normalized fixed sort: #{normalized_sort.inspect}"
    sorted_ids = sort_ids_with_state(ids, normalized_sort, duplicate_values: true)
    debug_puts "[DEBUG] Fixed sorted IDs: #{sorted_ids.inspect}"
    sorted_ids
  end

  #
  # 現在のソート状態を日本語で表示する文字列を生成
  #
  def current_sort_display_string
    server_setting = Inventory.load("server_setting", :global)
    current_sort = normalize_sort_state(server_setting["current_sort"])
    return "ID順" unless current_sort

    column_display = sort_column_label(current_sort) || "不明"
    dir_display = current_sort["dir"] == "desc" ? "降順" : "昇順"

    "#{column_display}#{dir_display}"
  end

  private

  def normalize_sort_state(sort_state)
    return nil unless sort_state.is_a?(Hash)

    order_column = sort_state["column"] || sort_state[:column]
    order_dir = sort_state["dir"] || sort_state[:dir]
    return nil if order_column.nil? || order_dir.nil?

    column_index = normalize_sort_column(order_column)
    return nil unless column_index

    direction = order_dir.to_s
    return nil unless %w[asc desc].include?(direction)

    {
      "column" => column_index,
      "dir" => direction
    }
  end
  module_function :normalize_sort_state

  def sort_column_name(sort_state)
    normalized_sort = normalize_sort_state(sort_state)
    return nil unless normalized_sort

    SORT_COLUMN_KEYS[normalized_sort["column"]]
  end
  module_function :sort_column_name

  def sort_column_label(sort_state)
    normalized_sort = normalize_sort_state(sort_state)
    return nil unless normalized_sort

    SORT_COLUMN_LABELS[normalized_sort["column"]]
  end
  module_function :sort_column_label

  def normalize_sort_column(order_column)
    if order_column.is_a?(Integer)
      return order_column if SORT_COLUMN_KEYS[order_column]
      return nil
    end

    return nil unless order_column.is_a?(String) && order_column.match?(/\A\d+\z/)

    column_index = order_column.to_i
    SORT_COLUMN_KEYS[column_index] ? column_index : nil
  end

  def sort_ids_with_state(ids, sort_state, duplicate_values: false)
    return ids unless sort_state

    sort_column = sort_column_name(sort_state)
    return ids unless sort_column

    database = Database.instance
    novels_data = ids.filter_map do |id|
      data = database[id.to_i]
      next unless data

      [id, duplicate_values ? data.dup : data]
    end

    debug_puts "[DEBUG] Found #{novels_data.length} novels with data for #{sort_column}"
    debug_puts "[DEBUG] Before sort: #{novels_data.map { |novel| [novel[0], novel[1][sort_column]] }.inspect}"

    novels_data.sort! do |a, b|
      val_a = a[1][sort_column] || 0
      val_b = b[1][sort_column] || 0
      comparison = compare_sort_values(val_a, val_b)
      result = sort_state["dir"] == "desc" ? -comparison : comparison
      debug_puts "[DEBUG] Comparing ID #{a[0]} (#{val_a}) vs ID #{b[0]} (#{val_b}) => #{result}"
      result
    end

    debug_puts "[DEBUG] After sort: #{novels_data.map { |novel| [novel[0], novel[1][sort_column]] }.inspect}"
    novels_data.map { |novel| novel[0] }
  end

  def compare_sort_values(val_a, val_b)
    if val_a.is_a?(Numeric) && val_b.is_a?(Numeric)
      val_a <=> val_b
    else
      val_a.to_s <=> val_b.to_s
    end
  end
  module_function :compare_sort_values

  def debug_puts(message)
    puts message if ENV["NAROU_DEBUG"] == "1"
  end

  #
  # フォーム情報の真偽値データを実際のデータに変換
  #
  def convert_on_off_to_boolean(str)
    case str
    when "on"
      true
    when "off"
      false
    else
      nil
    end
  end

  #
  # nil true false を nil on off という文字列に変換
  #
  def convert_boolean_to_on_off(bool)
    case bool
    when TrueClass
      "on"
    when FalseClass
      "off"
    else
      "nil"
    end
  end

  #
  # HTMLエスケープヘルパー
  #
  def h(text)
    Rack::Utils.escape_html(text)
  end

  #
  # 与えられたデータが真偽値だった場合、設定画面用に「はい」「いいえ」に変換する
  # 真偽値ではなかった場合、そのまま返す
  #
  def value_to_msg(value)
    case value
    when TrueClass
      "はい"
    when FalseClass
      "いいえ"
    else
      value
    end
  end

  def notepad_text_path
    File.join(Narou.local_setting_dir, "notepad.txt")
  end

  def query_to_boolean(value, default: false)
    case value
    when "1", 1, "true", true
      true
    when "0", 0, "false", false
      false
    else
      default
    end
  end

  def table_reload_timing
    Inventory.load("local_setting")["webui.table.reload-timing"] || RELOAD_TIMING_DEFAULT
  end

  def partial(template, *args)
    template_file_name = "_#{template}".intern
    options = args.last.is_a?(Hash) ? args.pop : {}
    options[:layout] = false
    collection = options.delete(:collection)
    if collection
      collection.inject([]) do |buffer, member|
        buffer << haml(template_file_name, options.merge(locals: { template => member }))
      end.join("\n")
    else
      haml(template_file_name, options)
    end
  end

  def embed_concurrency_enabled
    <<~HTML
      <input type="hidden" id="concurrency-enabled" value="#{Narou.concurrency_enabled?}">
    HTML
  end

  def embed_performance_mode
    local_setting = Inventory.load("local_setting")
    performance_mode = local_setting["webui.performance-mode"] || "auto"
    <<~HTML
      <input type="hidden" id="performance-mode" value="#{performance_mode}">
    HTML
  end

  def concurrency_push(&block)
    if Narou.concurrency_enabled?
      Narou.concurrency_call(&block)
    else
      Narou::WebWorker.push(&block)
    end
  end
end
