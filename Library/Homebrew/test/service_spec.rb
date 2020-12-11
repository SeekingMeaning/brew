# typed: false
# frozen_string_literal: true

require "formula"
require "service"

describe Homebrew::Service do
  let(:f) do
    class TestFormula < Formula
      url "https://brew.sh/test-1.0.tbz"
      service do
        run [bin/"beanstalkd"]
        run_type :immediate
        error_log_path "#{var}/log/beanstalkd.error.log"
        log_path var "#{var}/log/beanstalkd.log"
        working_dir var
        keep_alive true
      end
    end
  end
  let(:service) { described_class.new(f) }

  describe "#to_plist" do
    it "returns valid PLIST" do
      plist = service.to_plist
      expect(plist).to include("<key>Label</key>")
      expect(plist).to include("<key>KeepAlive</key>")
      expect(plist).to include("<key>RunAtLoad</key>")
      expect(plist).to include("<key>ProgramArguments</key>")
      expect(plist).to include("<key>WorkingDirectory</key>")
      expect(plist).to include("<key>StandardOutPath</key>")
      expect(plist).to include("<key>StandardErrorPath</key>")
    end
  end
end
