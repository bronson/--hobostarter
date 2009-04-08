module Hobo

  module Lifecycles

    class LifecycleError < RuntimeError; end

    class LifecycleKeyError < LifecycleError; end

    ModelExtensions = classy_module do

      attr_writer :lifecycle
      
      def self.has_lifecycle?
        defined?(self::Lifecycle)
      end
      
      def self.lifecycle(*args, &block)
        options = args.extract_options!
        options = options.reverse_merge(:state_field => :state,
                                        :key_timestamp_field => :key_timestamp)

        if defined? self::Lifecycle
          lifecycle = self::Lifecycle
        else
          # First call
          
          module_eval "class ::#{name}::Lifecycle < Hobo::Lifecycles::Lifecycle; end"
          lifecycle = self::Lifecycle
          lifecycle.init(self, options)
        end

        dsl = DeclarationDSL.new(lifecycle)
        dsl.instance_eval(&block)

        default = lifecycle.default_state ? { :default => lifecycle.default_state.name.to_s } : {}
        declare_field(options[:state_field], :string, default)
        never_show      options[:state_field]
        attr_protected  options[:state_field]

        unless options[:key_timestamp_field] == false
          declare_field(options[:key_timestamp_field], :datetime)
          never_show      options[:key_timestamp_field]
          attr_protected  options[:key_timestamp_field]
        end
        
      end
      
      
      def self.validation_method_with_lifecycles(on)
        if has_lifecycle? && self::Lifecycle.step_names.include?(on)
          callback = :"validate_on_#{on}"
          
          # define these lifecycle validation callbacks on demand
          define_callbacks callback unless respond_to? :callback
          define_method(callback) {}
          
          callback
        else
          validation_method_without_lifecycles(on)
        end
      end
      metaclass.alias_method_chain :validation_method, :lifecycles
      
      
      def valid_with_lifecycles?
        valid_without_lifecycles?
        
        if self.class.has_lifecycle? && (step = lifecycle.active_step) && respond_to?(cb = "validate_on_#{step.name}")
          run_callbacks cb
        end

        errors.empty?
      end
      alias_method_chain :valid?, :lifecycles


      def lifecycle
        @lifecycle ||= self.class::Lifecycle.new(self)
      end

    end


    class DeclarationDSL

      def initialize(lifecycle)
        @lifecycle = lifecycle
      end

      def state(*args, &block)
        options = args.extract_options!
        names = args
        states = names.map {|name| @lifecycle.def_state(name, block) }
        if options[:default]
          raise ArgumentError, "you must define one state if you give the :default option" unless states.length == 1
          @lifecycle.default_state = states.first
        end
      end

      def create(name, options={}, &block)
        @lifecycle.def_creator(name, block, options)
      end

      def transition(name, change, options={}, &block)
        @lifecycle.def_transition(name,
                                  Array(change.keys.first), change.values.first,
                                  block, options)
      end

      def invariant(&block)
        @lifecycle.invariants << block
      end

    end

  end
end
