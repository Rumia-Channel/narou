# -*- coding: utf-8 -*-
#
# Copyright 2013 whiteleaf. All rights reserved.
#
# auto generated at 2015-08-07 22:44:33 +0900

require "commandline"
require "narou_logger"
require_relative "../../lib/command/update/scheduler"

describe Command::Update do
  describe "--ignore-all" do
    it "should be blank" do
      cap = $stdout.capture {
        CommandLine.run!(%w(update --ignore-all))
      }.strip
      expect(cap).to eq ""
    end

    it "should not be blank" do
      cap = $stdout.capture(quiet: true) {
        CommandLine.run!(%w(update --ignore-all 22))
      }.strip
      expect(cap).to eq "ID:22　もう一度ナデシコへ は凍結中です"
    end
  end

  describe Command::Update::Scheduler do
    describe ".build_auto_update_sort_argv" do
      it "uses the WebUI sort setting when the stored sort column is valid" do
        allow(Inventory).to receive(:load).with("server_setting", :global).and_return(
          "current_sort" => { "column" => "2", "dir" => "desc" }
        )

        expect(described_class.build_auto_update_sort_argv).to eq(["--sort-by", "general_lastup"])
      end
    end
  end
end
