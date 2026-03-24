require_relative "spec_helper"
require_relative "../lib/web/server_helpers"

describe Narou::ServerHelpers do
  let(:helper_host) do
    Class.new do
      include Narou::ServerHelpers
    end.new
  end

  describe ".normalize_sort_state" do
    it "normalizes string column indexes" do
      expect(described_class.normalize_sort_state({ "column" => "4", "dir" => :desc })).to eq(
        "column" => 4,
        "dir" => "desc"
      )
    end

    it "rejects invalid column indexes" do
      expect(described_class.normalize_sort_state({ "column" => "title", "dir" => "asc" })).to be_nil
    end
  end

  describe "#sort_ids_by_current_sort" do
    it "sorts ids using string-based current_sort values from server settings" do
      allow(Inventory).to receive(:load).with("server_setting", :global).and_return(
        "current_sort" => { "column" => "4", "dir" => "asc" }
      )
      database = instance_double("Database")
      allow(Database).to receive(:instance).and_return(database)
      allow(database).to receive(:[]).with(2).and_return("title" => "Zeta")
      allow(database).to receive(:[]).with(1).and_return("title" => "Alpha")

      expect(helper_host.sort_ids_by_current_sort(%w[2 1])).to eq(%w[1 2])
    end
  end

  describe "#current_sort_display_string" do
    it "renders the current sort label when the stored column is a string" do
      allow(Inventory).to receive(:load).with("server_setting", :global).and_return(
        "current_sort" => { "column" => "4", "dir" => "desc" }
      )

      expect(helper_host.current_sort_display_string).to eq("タイトル降順")
    end
  end
end
