require 'evd/protocol'
require 'evd/plugin'
require 'evd/logging'

require 'eventmachine'

require 'beefcake'

require 'riemann/query'
require 'riemann/attribute'
require 'riemann/state'
require 'riemann/event'
require 'riemann/message'

module EVD::Plugin
  module Riemann
    include EVD::Plugin
    include EVD::Logging

    register_plugin "riemann"

    MAPPING = [
      [:key, :service, :service=],
      [:value, :metric, :metric=],
      [:host, :host, :host=],
      [:state, :state, :state=],
      [:description, :description, :description=],
      [:ttl, :ttl, :ttl=],
    ]

    module RiemannUtils
      private

      def make_event(event)
        tags = @tags
        tags += event.tags unless event.tags.nil?
        tags = tags.map{|v| v.dup}

        unless event.attributes.nil?
          attributes = @attributes.merge(event.attributes)
        else
          attributes = @attributes
        end

        e = ::Riemann::Event.new

        unless attributes.empty?
          attributes = attributes.map{|k, v|
            ::Riemann::Attribute.new(:key => k.dup, :value => v.dup)
          }

          e.attributes = attributes unless attributes.empty?
        end

        unless tags.empty?
          e.tags = tags
        end

        MAPPING.each do |key, reader, writer|
          next if (v = event.send(key)).nil?
          e.send(writer, v)
        end

        if time = event.send(:time)
          e.time = time.to_i
        end

        e
      end

      def read_event(event)
        input = {}

        unless event.attributes.nil?
          attributes = {}

          event.attributes.each do |attr|
            attributes[attr.key] = attr.value
          end

          input[:attributes] = attributes unless attributes.empty?
        end

        unless event.tags.nil? or event.tags.empty?
          input[:tags] = Set.new(event.tags)
        end

        MAPPING.each do |key, reader, writer|
          next if (v = event.send(reader)).nil?
          input[key] = v
        end

        if time = event.send(:time)
          input[:time] = Time.at(time)
        end

        input
      end

      def make_message(message)
        ::Riemann::Message.new(message)
      end

      def read_message(data)
        ::Riemann::Message.decode data
      end
    end

    module HandlerMixin
      def initialize(tags, attributes)
        @tags = Set.new(tags || [])
        @attributes = attributes || {}
        @bad_acks = 0
      end

      def receive_data(data)
        message = read_message data
        return if message.ok
        @bad_acks += 1
      end

      def serialize_all(events)
        events = events.map{|e| make_event e}
        m = make_message :events => events
        encode m
      end

      def serialize(event)
        e = make_event event
        m = make_message :events => [e]
        encode m
      end

      protected

      def encode(m); raise "Not implemented: encode"; end
    end

    class HandlerTCP
      include EVD::Logging
      include RiemannUtils
      include HandlerMixin

      def encode(m)
        m.encode_with_length
      end
    end

    class HandlerUDP
      include EVD::Logging
      include RiemannUtils
      include HandlerMixin

      def encode(m)
        m.encode
      end
    end

    class ConnectionBase < EM::Connection
      include EVD::Logging
      include RiemannUtils
      include EM::Protocols::ObjectProtocol

      module RiemannSerializer
        def self.dump(m)
          m.encode.to_s
        end

        def self.load(data)
          ::Riemann::Message.decode(data)
        end
      end

      def initialize(channel, log)
        @events = channel.events
        @log = log
      end

      def serializer
        RiemannSerializer
      end

      def receive_object(m)
        m.events.each do |e|
          @events << read_event(e)
        end

        send_ok
      rescue => e
        @log.error "Failed to receive object", e
        send_error e
      end

      protected

      def send_ok; end
      def send_error(e); end
    end

    class ConnectionTCP < ConnectionBase
      def send_ok
        send_object(::Riemann::Message.new(
          :ok => true))
      end

      def send_error(e)
        send_object(::Riemann::Message.new(
          :ok => false, :error => e.to_s))
      end
    end

    class ConnectionUDP < ConnectionBase; end

    DEFAULT_HOST = "localhost"
    DEFAULT_PORT = 5555
    DEFAULT_PROTOCOL = 'tcp'

    HANDLERS = {
      :tcp => HandlerTCP,
      :udp => HandlerUDP,
    }

    def self.output_setup(opts={})
      opts[:host] ||= DEFAULT_HOST
      opts[:port] ||= DEFAULT_PORT

      attributes = opts[:attributes] || {}
      tags = opts[:tags] || []
      protocol = EVD.parse_protocol(opts[:protocol] || DEFAULT_PROTOCOL)

      if (handler = HANDLERS[protocol.family]).nil?
        raise "No handler for protocol family: #{protocol.family}"
      end

      handler_instance = handler.new tags, attributes
      protocol.connect log, opts, handler_instance
    end

    def self.input_setup(opts={})
      opts[:host] ||= DEFAULT_HOST
      opts[:port] ||= DEFAULT_PORT
      protocol = EVD.parse_protocol(opts[:protocol] || DEFAULT_PROTOCOL)

      if protocol.family == :udp
        connection = ConnectionUDP
      else
        connection = ConnectionTCP
      end

      protocol.listen log, opts, connection, log
    end
  end
end
