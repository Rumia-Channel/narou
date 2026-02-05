# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "json"
require "singleton"
require_relative "web-socket-ruby/lib/web_socket"
require_relative "../eventable"

module Narou
  class PushServer
    include Singleton
    include Eventable

    HISTORY_SAVED_COUNT = 60 # 保存する履歴の数
    CONNECTION_CLEANUP_INTERVAL = 60 # 定期クリーンアップの間隔（秒）

    attr_accessor :port, :host
    attr_reader :accepted_domains, :connections

    def accepted_domains=(domains)
      @accepted_domains = Array(domains)
    end

    def initialize
      @accepted_domains = ["*"]
      @port = 31000
      @connections = []
      @connections_mutex = Mutex.new
      @server_thread = nil
      @cleanup_thread = nil
      clear_history
    end

    def run
      @server = WebSocketServer.new({
        accepted_domains: @accepted_domains,
        port: @port,
        host: @host
      })

      # 定期的にデッドコネクションをクリーンアップするスレッド
      start_cleanup_thread

      @server_thread = Thread.new do
        @server.run do |ws|
          que = nil
          thread = nil
          connection_entry = nil
          begin
            ws.handshake
            que = Queue.new

            thread = Thread.new do
              begin
                while true
                  data = que.pop
                  ws.send(data)
                end
              rescue Errno::ECONNRESET, Errno::EPIPE, IOError => e
                # 接続が切れた場合、スレッドを終了
              rescue => e
                # その他のエラーもログに出力してスレッド終了
                puts "[ERROR] WebSocket send thread error: #{e.class}: #{e.message}" if $DEBUG
              end
            end

            # コネクション情報を登録
            connection_entry = { queue: que, thread: thread }
            @connections_mutex.synchronize do
              @connections.push(connection_entry)
            end

            @history.compact.each do |message|
              ws.send(JSON.generate(echo: message))
            end

            while data = ws.receive
              begin
                JSON.parse(data).each do |name, value|
                  trigger(name, value, ws)
                end
              rescue JSON::ParserError => e
                ws.send(JSON.generate(echo: {
                  target_console: "#console",
                  body: e.message
                }))
              end
            end
          rescue WebSocket::Error => e
            # WebSocketハンドシェイクエラー（通常はクライアントの切断）
            # デバッグレベルでログ出力（エラーレベルだと大量に出力される）
            puts "[DEBUG] WebSocket handshake failed: #{e.message}" if $DEBUG
          rescue Errno::ECONNRESET => e
            # 接続リセットエラー
            puts "[DEBUG] WebSocket connection reset: #{e.message}" if $DEBUG
          rescue StandardError => e
            # その他の予期しないエラー
            puts "[ERROR] WebSocket unexpected error: #{e.class}: #{e.message}"
            puts e.backtrace.first(5).join("\n") if $DEBUG
          ensure
            @connections_mutex.synchronize do
              @connections.delete(connection_entry) if connection_entry
            end
            thread.terminate if thread
          end
        end
      end
    end

    #
    # PushServer を停止させる
    #
    def quit
      @server.quit if @server
      if @cleanup_thread && @cleanup_thread.alive?
        @cleanup_thread.kill
        @cleanup_thread.join(0.5)
      end
      if @server_thread && @server_thread.alive?
        @server_thread.kill
        @server_thread.join(1) # 最大1秒待つ
      end
    end

    def clear_history
      @history = [nil] * HISTORY_SAVED_COUNT
      # Sinatra で get "/" { clear_history } とかやった場合に [nil,nil...] な配列データが
      # 渡されないようにするため（配列は Sinatra にとって特別なデータ）
      true
    end

    #
    # 接続している全てのクライアントに対してメッセージを送信
    #
    def send_all(data)
      if data.kind_of?(Symbol)
        # send_all(:"events.name") としてイベント名だけで送りたい場合の対応
        data = { data => true }
      end
      json = JSON.generate(data)

      dead_connections = []
      @connections_mutex.synchronize do
        @connections.each do |connection_entry|
          # スレッドが生きている場合のみメッセージを送信
          if connection_entry[:thread]&.alive?
            begin
              connection_entry[:queue].push(json)
            rescue => e
              # push に失敗した場合、デッドコネクションとしてマーク
              puts "[DEBUG] Failed to push to queue: #{e.message}" if $DEBUG
              dead_connections << connection_entry
            end
          else
            # スレッドが死んでいる場合、デッドコネクションとしてマーク
            dead_connections << connection_entry
          end
        end

        # デッドコネクションを削除
        dead_connections.each do |dead_conn|
          @connections.delete(dead_conn)
        end
      end

      # echo 以外のイベントは履歴に保存しない
      message = data[:echo]
      if message
        stack_to_history(message)
      end
    rescue JSON::GeneratorError => e
      STDERR.puts $@.shift + ": #{e.message} (#{e.class})"
    end

    def stack_to_history(message)
      return if message[:no_history]
      if message[:body] == "." && (last = @history[-1])[:body] =~ /\A\.+\z/
        # 進行中を表す .... の出力でヒストリーが消費されるのを防ぐため、
        # 連続した . は一つにまとめる
        last[:body] = "#{last[:body]}."
      else
        @history.push(message)
        @history.shift
      end
    end

    private

    #
    # 定期的にデッドコネクションをクリーンアップするスレッドを起動
    #
    def start_cleanup_thread
      @cleanup_thread = Thread.new do
        loop do
          sleep CONNECTION_CLEANUP_INTERVAL
          cleanup_dead_connections
        end
      rescue => e
        puts "[ERROR] Cleanup thread error: #{e.class}: #{e.message}" if $DEBUG
      end
    end

    #
    # デッドコネクション（スレッドが死んでいる接続）を削除
    #
    def cleanup_dead_connections
      dead_connections = []
      @connections_mutex.synchronize do
        @connections.each do |connection_entry|
          unless connection_entry[:thread]&.alive?
            dead_connections << connection_entry
          end
        end

        if dead_connections.any?
          dead_connections.each do |dead_conn|
            @connections.delete(dead_conn)
          end
          puts "[DEBUG] Cleaned up #{dead_connections.size} dead connection(s)" if $DEBUG
        end
      end
    end
  end
end
