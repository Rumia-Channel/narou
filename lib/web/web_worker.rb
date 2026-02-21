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
      @queue = Queue.new
      @size = 0
      @mutex = Mutex.new
      @worker_thread = nil
      @push_server = Narou::PushServer.instance
      @cancel_signal = false
      @thread_of_block_executing = nil
      @pending_running_tasks = []
      @waiting_confirmation = false
    end

    def waiting_confirmation?
      @waiting_confirmation
    end

    def get_pending_running_tasks
      @pending_running_tasks.dup
    end

    def process_confirmed_running_tasks(rerun: true)
      tasks_to_process = @mutex.synchronize do
        tasks = @pending_running_tasks
        @pending_running_tasks = []
        @waiting_confirmation = false
        tasks
      end

      if rerun
        tasks_to_process.each do |task|
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
      else
        tasks_to_process.each do |task|
          PersistentQueue.complete(task["id"])
        end
      end
    end

    def running?
      !@worker_thread.!
    end

    def start
      return if running?
      @worker_thread = Thread.new do
        loop do
          begin
            q = @queue.pop
            if canceled?
              @queue.clear
              @cancel_signal = false
            else
              task_id = q[:task_id]
              PersistentQueue.start(task_id) if task_id
              @thread_of_block_executing = Thread.new do
                q[:block]&.call
              end
              @thread_of_block_executing.join
              @thread_of_block_executing = nil
              PersistentQueue.complete(task_id) if task_id
            end
          rescue SystemExit
          rescue Exception => e
            output_error($stdout, e)
          ensure
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
      @mutex.synchronize do
        if @size > 0
          @cancel_signal = true
          @size = 0
          @thread_of_block_executing&.raise(Interrupt)
        end
      end
      Thread.pass
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
      @queue.push(block: block, task_id: task["id"], counting: true, cmd: cmd, args: args, meta: meta)
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
      @queue.push(block: block, task_id: task_id, counting: counting)
    end

    def notification_queue
      @push_server.send_all("notification.queue" => [@size, Narou::Worker.size])
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

    #
    # 未完了タスクの復元と再実行
    # 戻り値: 復元されたタスク数
    #
    def self.restore_and_execute_pending_tasks
      instance.restore_and_execute_pending_tasks
    end

    def restore_and_execute_pending_tasks(confirm_running: false)
      tasks = PersistentQueue.restore
      running_tasks = tasks.select { |t| t["status"] == "running" }
      pending_tasks = tasks.select { |t| t["status"] == "pending" }

      running_count = running_tasks.size
      pending_count = pending_tasks.size
      total_count = running_count + pending_count

      return 0 if total_count.zero?

      if running_count > 0
        @mutex.synchronize do
          @pending_running_tasks = running_tasks
          @waiting_confirmation = true
        end
        @push_server.send_all("queue.pending_running_tasks" => running_tasks)
        rerun_running = confirm_rerun_running_tasks(running_tasks)
        process_confirmed_running_tasks(rerun: rerun_running)
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

    def confirm_rerun_running_tasks(running_tasks)
      puts "<yellow>前回中断されたタスクが#{running_tasks.size}件あります:</yellow>".termcolor
      running_tasks.each do |task|
        puts "  - #{task['cmd']} #{(task['args'] || []).join(' ')}".termcolor
      end
      print "<yellow>再実行しますか？ [Y/n]: </yellow>".termcolor

      answer = $stdin.gets&.strip&.downcase
      answer.nil? || answer.empty? || answer == 'y' || answer == 'yes'
    rescue SystemCallError
      true
    end

    def self.has_pending_tasks?
      PersistentQueue.has_pending_or_running?
    end

    private

    def enqueue_restored_task(task, &block)
      countup
      @queue.push(
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
          puts "自動アップデート処理を開始します（復元）"
          begin
            update_command = Command.load_command("update").new
            update_command.execute(args)
            puts "自動アップデートが完了しました"
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
  end
end
