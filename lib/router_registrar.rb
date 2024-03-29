$:.unshift(File.expand_path(".", File.dirname(__FILE__)))

require "rubygems"
require "bundler/setup"

require "eventmachine"
require "nats/client"
require "vcap/logging"
require "vcap/common"

module RouterRegistrar

  class Config
    class << self
      [:logger, :nats_uri, :uri, :host, :port, :tags, :pid].each { |option| attr_accessor option }

      def configure(config)
        VCAP::Logging.setup_from_config(config["logging"])
        @logger = VCAP::Logging.logger("router_registrar")

        @nats_uri = config["mbus"]

        @uri = config["uri"]
        @host = config["host"]
        @port = config["port"]
        @tags = config["tags"]
        @pid  = config["pid"]
      end
    end
  end

  class RouterRegistrar
    ROUTER_START_TOPIC = "router.start"
    ROUTER_REGISTER_TOPIC = "router.register"
    ROUTER_UNREGISTER_TOPIC = "router.unregister"

    def initialize
      @logger = Config.logger
      
      create_pidfile

      @registration_message = Yajl::Encoder.encode({
        :host => Config.host,
        :port => Config.port,
        :uris => [Config.uri],
        :tags => Config.tags
      })

      NATS.on_error do |e|
        @logger.fatal("Exiting, NATS error")
        @logger.fatal(e)
        exit
      end

      @nats = NATS.connect(:uri => Config.nats_uri) do
        @logger.info("Connected to NATS")
        @nats.subscribe(ROUTER_START_TOPIC) do
          send_registration_message
        end
        send_registration_message
      end
    end

    def shutdown(&block)
      send_unregistration_message(&block)
    end

    def send_registration_message
      @logger.info("Sending registration: #{@registration_message}")
      @nats.publish(ROUTER_REGISTER_TOPIC, @registration_message)
    end

    def send_unregistration_message(&block)
      @logger.info("Sending unregistration: #{@registration_message}")
      @nats.publish(ROUTER_UNREGISTER_TOPIC, @registration_message, &block)
    end

    def create_pidfile
      begin
        pid_file = VCAP::PidFile.new(Config.pid)
        pid_file.unlink_at_exit
      rescue => e
        $stderr.puts "ERROR: Can't create pid file #{Config.pid}"
        exit 1
      end
    end
  end

end
