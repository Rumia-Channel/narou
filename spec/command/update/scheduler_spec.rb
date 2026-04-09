# frozen_string_literal: true

require_relative "../../../lib/command/update"

describe Command::Update::Scheduler do
  describe ".collect_auto_update_target_ids" do
    it "separates modified novels from non-API novels" do
      database = instance_double("Database", tag_indexies: { Narou::MODIFIED_TAG => [2, 4] })
      allow(Database).to receive(:instance).and_return(database)
      allow(database).to receive(:each).and_yield(1, {}).and_yield(2, {}).and_yield(3, {}).and_yield(4, {})

      api_setting = instance_double("SiteSetting")
      allow(api_setting).to receive(:[]).with("narou_api_url").and_return("https://api.example.test")
      allow(api_setting).to receive(:clear)

      non_api_setting = instance_double("SiteSetting")
      allow(non_api_setting).to receive(:[]).with("narou_api_url").and_return(nil)
      allow(non_api_setting).to receive(:clear)

      allow(Downloader).to receive(:get_sitesetting_by_target).with(1).and_return(api_setting)
      allow(Downloader).to receive(:get_sitesetting_by_target).with(2).and_return(non_api_setting)
      allow(Downloader).to receive(:get_sitesetting_by_target).with(3).and_return(non_api_setting)
      allow(Downloader).to receive(:get_sitesetting_by_target).with(4).and_return(non_api_setting)

      modified_ids, other_ids = described_class.collect_auto_update_target_ids

      expect(modified_ids).to eq(%w[2 4])
      expect(other_ids).to eq(%w[3])
    end
  end

  describe ".run_auto_update_job" do
    it "runs narou check, modified update, and other update in order" do
      allow(described_class).to receive(:build_auto_update_sort_argv).and_return(["--sort-by", "general_lastup"])
      allow(described_class).to receive(:collect_auto_update_target_ids).and_return([%w[10 20], %w[30]])

      update_command_gl = instance_double(Command::Update)
      update_command_modified = instance_double(Command::Update)
      update_command_other = instance_double(Command::Update)
      allow(Command::Update).to receive(:new).and_return(update_command_gl, update_command_modified, update_command_other)

      expect(update_command_gl).to receive(:execute).with(["--gl", "narou"])
      expect(update_command_modified).to receive(:execute).with(["--sort-by", "general_lastup", "10", "20"])
      expect(update_command_other).to receive(:execute).with(["--sort-by", "general_lastup", "30"])

      expect(described_class.run_auto_update_job).to be true
    end
  end
end
