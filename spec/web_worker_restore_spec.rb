# frozen_string_literal: true

require "pathname"
require "tmpdir"
require_relative "../lib/web/web_worker"

describe Narou::WebWorker do
  around do |example|
    Dir.mktmpdir do |dir|
      allow(Narou).to receive(:local_setting_dir).and_return(Pathname(dir))
      push_server = instance_double(Narou::PushServer, send_all: nil)
      allow(Narou::PushServer).to receive(:instance).and_return(push_server)
      Narou::PersistentQueue.instance_variable_set(:@instance, nil)
      described_class.instance_variable_set(:@instance, nil)
      example.run
      described_class.instance.stop
      described_class.instance_variable_set(:@instance, nil)
      Narou::PersistentQueue.instance_variable_set(:@instance, nil)
    end
  end

  let(:worker) { described_class.instance }
  let(:queue) { Narou::PersistentQueue.instance }

  it "reorders deferred pending tasks before they are enqueued" do
    first = queue.push("download", ["n0001"])
    second = queue.push("update", ["n0002"])

    worker.mark_restorable_tasks_available

    expect(worker.reorder_pending_tasks([second["id"], first["id"]])).to be true
    expect(queue.get_pending_tasks.map { |task| task["id"] }).to eq([second["id"], first["id"]])
  end

  it "removes a deferred pending task before it is enqueued" do
    first = queue.push("download", ["n0001"])
    second = queue.push("update", ["n0002"])

    worker.mark_restorable_tasks_available

    expect(worker.remove_pending_task(first["id"])).to be true
    expect(queue.get_pending_tasks.map { |task| task["id"] }).to eq([second["id"]])
  end

  it "resumes deferred tasks from the persistent queue" do
    interrupted = queue.push("download_force", ["1969"])
    queue.start(interrupted["id"])
    pending = queue.push("auto_update", [])

    worker.mark_restorable_tasks_available
    allow(worker).to receive(:build_block_from_task).and_return(-> {})

    expect(worker.resume_restorable_tasks).to eq(2)
    expect(queue.get_running_tasks).to be_empty
    expect(worker.size).to eq(2)
    expect(worker.instance_variable_get(:@queue).map { |entry| entry[:task_id] }).to eq([interrupted["id"], pending["id"]])
    expect(worker.restore_prompt_pending?).to be false
    expect(worker.restorable_tasks_available?).to be false
  end
end
