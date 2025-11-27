module Helper
  class EbookConverterQueue
    def initialize
      @queue = Queue.new
      @thread = Thread.new do
        loop do
          task = @queue.pop
          break if task == :stop
          begin
            task.call
          rescue => e
            $stdout2.error "Ebook変換キューでエラーが発生しました: #{e.message}"
          ensure
            # メモリ解放のためのGC（任意）
            GC.start
          end
        end
      end
    end

    def push(&block)
      @queue.push(block)
    end

    def shutdown
      @queue.push(:stop)
      @thread.join
    end
  end
end
