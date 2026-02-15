# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "yaml"
require "securerandom"
require "monitor"
require "fileutils"
require_relative "narou"

module Narou
  #
  # 永続化対応ジョブキュー
  # クラッシュや503エラーなどでプロセスが終了しても、
  # 再起動後に未完了タスクを復元・再実行できる
  #
  class PersistentQueue
    include MonitorMixin

    QUEUE_FILE_NAME = "queue.yaml"
    STATUS_PENDING = "pending"
    STATUS_RUNNING = "running"
    STATUS_COMPLETED = "completed"

    attr_reader :pending_count, :running_count

    class << self
      def instance
        @instance ||= new
      end

      def push(cmd, args = [], meta = {})
        instance.push(cmd, args, meta)
      end

      def start(task_id)
        instance.start(task_id)
      end

      def complete(task_id)
        instance.complete(task_id)
      end

      def get_pending_tasks
        instance.get_pending_tasks
      end

      def get_running_tasks
        instance.get_running_tasks
      end

      def restore
        instance.restore
      end

      def clear_completed
        instance.clear_completed
      end

      def pending_count
        instance.pending_count
      end

      def running_count
        instance.running_count
      end

      def has_pending_or_running?
        instance.has_pending_or_running?
      end

      def queue_file_path
        instance.queue_file_path
      end
    end

    def initialize
      super
      @pending = []
      @running = []
      @pending_count = 0
      @running_count = 0
      load_from_file
    end

    def queue_file_path
      return nil unless Narou.local_setting_dir
      Narou.local_setting_dir.join(QUEUE_FILE_NAME)
    end

    def push(cmd, args = [], meta = {})
      synchronize do
        task = create_task(cmd, args, meta)
        @pending << task
        @pending_count = @pending.size
        save_to_file
        task
      end
    end

    def start(task_id)
      synchronize do
        task = @pending.find { |t| t["id"] == task_id }
        if task
          @pending.delete(task)
          task["status"] = STATUS_RUNNING
          task["started_at"] = Time.now.iso8601
          @running << task
          @pending_count = @pending.size
          @running_count = @running.size
          save_to_file
          true
        else
          false
        end
      end
    end

    def complete(task_id)
      synchronize do
        task = @running.find { |t| t["id"] == task_id }
        if task
          @running.delete(task)
          task["status"] = STATUS_COMPLETED
          task["completed_at"] = Time.now.iso8601
          @running_count = @running.size
          save_to_file
          true
        else
          false
        end
      end
    end

    def get_pending_tasks
      synchronize { @pending.dup }
    end

    def get_running_tasks
      synchronize { @running.dup }
    end

    def restore
      synchronize do
        load_from_file
        @pending + @running
      end
    end

    def clear_completed
      synchronize do
        save_to_file
      end
    end

    def has_pending_or_running?
      synchronize do
        @pending.any? || @running.any?
      end
    end

    private

    def create_task(cmd, args, meta)
      {
        "id" => SecureRandom.uuid,
        "cmd" => cmd,
        "args" => args,
        "meta" => meta,
        "status" => STATUS_PENDING,
        "created_at" => Time.now.iso8601
      }
    end

    def load_from_file
      path = queue_file_path
      @pending = []
      @running = []

      return unless path && File.exist?(path)

      begin
        data = YAML.safe_load_file(path, permitted_classes: [Time])
        if data.is_a?(Hash)
          @pending = Array(data["pending"]).select { |t| valid_task?(t) }
          @running = Array(data["running"]).select { |t| valid_task?(t) }
        end
      rescue Psych::SyntaxError, Errno::ENOENT => e
        warn "[PersistentQueue] 読み込みエラー: #{e.message}"
      end

      @pending_count = @pending.size
      @running_count = @running.size
    end

    def save_to_file
      path = queue_file_path
      return unless path

      data = {
        "pending" => @pending,
        "running" => @running,
        "updated_at" => Time.now.iso8601
      }

      begin
        dir = path.dirname
        FileUtils.mkdir_p(dir) unless dir.exist?
        File.write(path, data.to_yaml)
      rescue Errno::ENOENT, Errno::EACCES => e
        warn "[PersistentQueue] 保存エラー: #{e.message}"
      end
    end

    def valid_task?(task)
      task.is_a?(Hash) && task["id"] && task["cmd"]
    end
  end
end
