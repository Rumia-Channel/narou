# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "singleton"
require_relative "pushserver"
require_relative "../mixin/all"
require_relative "../persistent_queue"

module Narou
  class WebWorker
    include Singleton
    include Mixin::OutputError

    attr_reader :size

    def self.run
      instance.start
    end

    def initialize
      @queue = []
      @queue_mutex = Mutex.new
      @queue_condition = ConditionVariable.new
      @size = 0
      @mutex = Mutex.new
      @worker_thread = nil
      @push_server = Narou::PushServer.instance
      @cancel_signal = false
      @thread_of_block_executing = nil
      @active_task_id = nil
      @restore_prompt_pending = false
      @restorable_tasks_available = false
    end

    def restore_prompt_pending?
      @mutex.synchronize { @restore_prompt_pending }
    end

    def restorable_tasks_available?
      @mutex.synchronize { @restorable_tasks_available } && PersistentQueue.has_pending_or_running?
    end

    def mark_restorable_tasks_available
      has_tasks = PersistentQueue.has_pending_or_running?

      @mutex.synchronize do
        @restore_prompt_pending = has_tasks
        @restorable_tasks_available = has_tasks
      end

      has_tasks
    end

    def self.reorder_pending_tasks(task_ids)
      instance.reorder_pending_tasks(task_ids)
    end

    def reorder_pending_tasks(task_ids)
      task_ids = Array(task_ids).map(&:to_s)
      reordered = false

      @queue_mutex.synchronize do
        pending_entries = @queue.select { |entry| entry[:task_id] }
        pending_ids = pending_entries.map { |entry| entry[:task_id].to_s }
        return PersistentQueue.reorder_pending(task_ids) if pending_entries.empty? && restorable_tasks_available?
        return false unless task_ids.size == pending_ids.size && task_ids.sort == pending_ids.sort

        entries_by_id = pending_entries.each_with_object({}) do |entry, hash|
          hash[entry[:task_id].to_s] = entry
        end
        reordered_entries = task_ids.map { |task_id| entries_by_id.fetch(task_id) }
        reordered_queue = []
        reorder_index = 0

        @queue.each do |entry|
          if entry[:task_id]
            reordered_queue << reordered_entries[reorder_index]
            reorder_index += 1
          else
            reordered_queue << entry
          end
        end

        @queue = reordered_queue
        reordered = true
      end

      reordered && PersistentQueue.reorder_pending(task_ids)
    end

    def self.remove_pending_task(task_id)
      instance.remove_pending_task(task_id)
    end

    def remove_pending_task(task_id)
      task_id = task_id.to_s
      removed_entry = nil

      @queue_mutex.synchronize do
        index = @queue.index { |entry| entry[:task_id].to_s == task_id }
        removed_entry = @queue.delete_at(index) if index
      end

      if removed_entry
        return false unless PersistentQueue.remove_pending(task_id)

        countdown if removed_entry[:counting]
        return true
      end

      removed = PersistentQueue.remove_pending(task_id)
      return false unless removed

      sync_restore_state
      notification_queue
      true
    end

    def running?
      !@worker_thread.!
    end

    def start
      return if running?
      @worker_thread = Thread.new do
        loop do
          q = nil
          begin
            q = pop_queue_item
            @cancel_signal = false
            task_id = q[:task_id]
            @active_task_id = task_id
            PersistentQueue.start(task_id) if task_id
            @thread_of_block_executing = Thread.new do
              q[:block]&.call
            end
            @thread_of_block_executing.join
            @thread_of_block_executing = nil
            PersistentQueue.complete(task_id) if task_id
          rescue SystemExit
          rescue Interrupt
          rescue Exception => e
            output_error($stdout, e)
          ensure
            @active_task_id = nil
            if q && q[:counting]
              countdown
            end
          end
        end
      end
    end

    def self.cancel
      instance.cancel
    end

    def cancel
      discarded_task_ids = []
      active_task_id = nil

      @mutex.synchronize do
        if @size > 0
          @cancel_signal = true
          active_task_id = @active_task_id
          @size = 0
          @thread_of_block_executing&.raise(Interrupt)
        end
      end

      discarded_task_ids = clear_pending_queue_entries
      discarded_task_ids.each do |task_id|
        PersistentQueue.remove_pending(task_id)
      end
      PersistentQueue.discard(active_task_id) if active_task_id

      @mutex.synchronize do
        @cancel_signal = false
        notification_queue
      end
      Thread.pass
    end

    def self.cancel_active_task(task_id)
      instance.cancel_active_task(task_id)
    end

    def cancel_active_task(task_id)
      task_id = task_id.to_s
      canceled = false

      @mutex.synchronize do
        return false unless @active_task_id.to_s == task_id
        return false unless @thread_of_block_executing

        @cancel_signal = true
        PersistentQueue.discard(task_id)
        @thread_of_block_executing.raise(Interrupt)
        canceled = true
      end

      Narou::Worker.cancel if canceled && Narou.concurrency_enabled?
      notification_queue if canceled
      Thread.pass if canceled
      canceled
    end

    def self.canceled?
      instance.canceled?
    end

    def canceled?
      @cancel_signal
    end

    def self.stop
      instance.stop
    end

    def stop
      @worker_thread&.kill
      @worker_thread = nil
    end

    #
    # システム用のワーカー追加。内部カウントは増やさない
    # 永続化しない
    #
    def self.push_as_system_worker(&block)
      instance.push(counting: false, persistent: false, &block)
    end

    #
    # 永続化対応のワーカー追加
    # cmd: コマンド名 ("download", "update", "convert" 等)
    # args: コマンド引数の配列
    # meta: 追加メタデータ (オプション)
    # block: 実行するブロック
    #
    def self.push_command(cmd, args = [], meta = {}, &block)
      instance.push_command(cmd, args, meta, &block)
    end

    def push_command(cmd, args = [], meta = {}, &block)
      countup
      task = PersistentQueue.push(cmd, args, meta)
      enqueue_task(block: block, task_id: task["id"], counting: true, cmd: cmd, args: args, meta: meta)
      task
    end

    #
    # 従来のブロック形式でのワーカー追加 (後方互換)
    # 永続化が必要な場合は push_command を使用すること
    #
    def self.push(&block)
      instance.push(&block)
    end

    def push(counting: true, persistent: false, cmd: nil, args: [], meta: {}, &block)
      countup if counting
      task_id = nil
      if persistent && cmd
        task = PersistentQueue.push(cmd, args, meta)
        task_id = task["id"]
      end
      enqueue_task(block: block, task_id: task_id, counting: counting)
    end

    def notification_queue
      @push_server.send_all("notification.queue" => [display_size, Narou::Worker.size])
    end

    def countup
      @mutex.synchronize do
        @size += 1
        notification_queue
      end
    end

    def countdown
      @mutex.synchronize do
        @size -= 1
        @size = 0 if @size < 0
        notification_queue
      end
    end

    def display_size
      [@size, PersistentQueue.pending_count + PersistentQueue.running_count].max
    end

    #
    # 未完了タスクの復元と再実行
    # 戻り値: 復元されたタスク数
    #
    def self.restore_and_execute_pending_tasks
      instance.resume_restorable_tasks
    end

    def resume_restorable_tasks
      tasks = PersistentQueue.restore
      running_tasks = tasks.select { |t| t["status"] == "running" }
      pending_tasks = tasks.select { |t| t["status"] == "pending" }

      running_count = running_tasks.size
      pending_count = pending_tasks.size
      total_count = running_count + pending_count

      return 0 if total_count.zero?

      @mutex.synchronize do
        @restore_prompt_pending = false
        @restorable_tasks_available = false
      end

      running_tasks.each do |task|
        cmd = task["cmd"]
        args = task["args"] || []
        meta = task["meta"] || {}
        puts "<yellow>[復元] 中断タスクを再実行します: #{cmd} #{args.join(' ')}</yellow>".termcolor
        block = build_block_from_task(cmd, args, meta)
        if block
          PersistentQueue.requeue(task["id"])
          enqueue_restored_task(task, &block)
        else
          PersistentQueue.discard(task["id"])
        end
      end

      pending_tasks.each do |task|
        cmd = task["cmd"]
        args = task["args"] || []
        meta = task["meta"] || {}
        puts "<yellow>[復元] タスクを再実行します: #{cmd} #{args.join(' ')}</yellow>".termcolor
        block = build_block_from_task(cmd, args, meta)
        if block
          enqueue_restored_task(task, &block)
        else
          PersistentQueue.discard(task["id"])
        end
      end

      total_count
    end

    def self.defer_restorable_tasks
      instance.defer_restorable_tasks
    end

    def defer_restorable_tasks
      PersistentQueue.get_running_tasks.each do |task|
        PersistentQueue.requeue(task["id"])
      end

      @mutex.synchronize do
        @restore_prompt_pending = false
        @restorable_tasks_available = PersistentQueue.has_pending_or_running?
      end

      notification_queue
    end

    def self.has_pending_tasks?
      PersistentQueue.has_pending_or_running?
    end

    private

    def enqueue_restored_task(task, &block)
      countup
      enqueue_task(
        block: block,
        task_id: task["id"],
        counting: true,
        cmd: task["cmd"],
        args: task["args"] || [],
        meta: task["meta"] || {}
      )
    end

    #
    # タスク情報から実行ブロックを再構築
    #
    def build_block_from_task(cmd, args, meta)
      case cmd
      when "download"
        lambda do
          CommandLine.run!("download", *args)
          Narou::AppServer.clear_all_cache
          @push_server.send_all(:"table.reload")
        end
      when "download_force"
        lambda do
          CommandLine.run!("download", "--force", *args)
          Narou::AppServer.clear_all_cache
          @push_server.send_all(:"table.reload")
        end
      when "update"
        lambda do
          cmd_instance = Command.load_command("update").new
          cmd_instance.execute!(args)
          Narou::AppServer.clear_all_cache
          @push_server.send_all(:"table.reload")
        end
      when "convert"
        lambda do
          Narou.concurrency_call do
            CommandLine.run!("convert", "--no-open", *args)
          end
        end
      when "mail"
        lambda do
          Narou.concurrency_call do
            CommandLine.run!("mail", args, io: $stdout2)
          end
        end
      when "send"
        lambda do
          Narou.concurrency_call do
            CommandLine.run!("send", args, io: $stdout2)
          end
        end
      when "freeze"
        lambda do
          CommandLine.run!("freeze", *args)
          Narou::AppServer.clear_all_cache
          @push_server.send_all(:"table.reload")
        end
      when "remove"
        lambda do
          CommandLine.run!("remove", "--yes", *args)
          @push_server.send_all(:"table.reload")
        end
      when "backup"
        lambda do
          CommandLine.run!("backup", *args)
        end
      when "inspect"
        lambda do
          CommandLine.run!("inspect", *args)
        end
      when "diff"
        lambda do
          CommandLine.run!("diff", *args)
        end
      when "diff_clean"
        lambda do
          CommandLine.run!("diff", "--clean", *args)
        end
      when "setting_burn"
        lambda do
          CommandLine.run!("setting", "--burn", *args)
        end
      when "update_general_lastup"
        lambda do
          CommandLine.run!(["update", "--gl", *args].compact)
          Narou::AppServer.clear_all_cache
          @push_server.send_all(:"table.reload")
          @push_server.send_all(:"tag.updateCanvas")
        end
      when "backup_bookmark"
        lambda do
          CommandLine.run!("send", "--backup-bookmark")
        end
      when "eject"
        lambda do
          Narou.concurrency_call do
            device = Narou.get_device
            device&.eject do
              puts "<bold><green>端末を取り外しました</green></bold>".termcolor
            end
          end
        end
      when "update_by_tag"
        lambda do
          cmd_instance = Command.load_command("update").new
          cmd_instance.execute!(args)
          Narou::AppServer.clear_all_cache
          @push_server.send_all(:"table.reload")
        end
      when "auto_update"
        lambda do
          begin
            Command::Update::Scheduler.run_auto_update_job(restored: true)
          rescue => e
            puts "自動アップデート処理中にエラーが発生しました: #{e.message}"
          end
          Narou::AppServer.clear_all_cache
          @push_server.send_all(:"table.reload")
        end
      else
        nil
      end
    end

    def enqueue_task(**task)
      @queue_mutex.synchronize do
        @queue << task
        @queue_condition.signal
      end
    end

    def pop_queue_item
      @queue_mutex.synchronize do
        @queue_condition.wait(@queue_mutex) while @queue.empty?
        @queue.shift
      end
    end

    def clear_pending_queue_entries
      @queue_mutex.synchronize do
        task_ids = @queue.filter_map { |entry| entry[:task_id]&.to_s }
        @queue.clear
        task_ids
      end
    end

    def sync_restore_state
      has_tasks = PersistentQueue.has_pending_or_running?

      @mutex.synchronize do
        @restore_prompt_pending = false unless has_tasks
        @restorable_tasks_available = has_tasks if @restorable_tasks_available
      end
    end
  end
end
