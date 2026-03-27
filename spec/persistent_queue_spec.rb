# frozen_string_literal: true

require "pathname"
require "tmpdir"
require_relative "../lib/persistent_queue"

describe Narou::PersistentQueue do
  around do |example|
    Dir.mktmpdir do |dir|
      allow(Narou).to receive(:local_setting_dir).and_return(Pathname(dir))
      described_class.instance_variable_set(:@instance, nil)
      example.run
      described_class.instance_variable_set(:@instance, nil)
    end
  end

  let(:queue) { described_class.instance }

  it "reorders pending tasks in the requested order" do
    first = queue.push("download", ["n0001"])
    second = queue.push("update", ["n0002"])
    third = queue.push("convert", ["n0003"])

    expect(queue.reorder_pending([third["id"], first["id"], second["id"]])).to be true
    expect(queue.get_pending_tasks.map { |task| task["id"] }).to eq([third["id"], first["id"], second["id"]])
  end

  it "removes a pending task" do
    first = queue.push("download", ["n0001"])
    second = queue.push("update", ["n0002"])

    expect(queue.remove_pending(first["id"])).to be true
    expect(queue.get_pending_tasks.map { |task| task["id"] }).to eq([second["id"]])
    expect(queue.pending_count).to eq(1)
  end

  it "rejects reorder requests that do not match the current pending tasks" do
    first = queue.push("download", ["n0001"])
    queue.push("update", ["n0002"])

    expect(queue.reorder_pending([first["id"]])).to be false
  end
end
