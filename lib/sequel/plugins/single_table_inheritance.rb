module Sequel
  module Plugins
    # The single_table_inheritance plugin allows storing all objects
    # in the same class hierarchy in the same table.  It makes it so
    # subclasses of this model only load rows related to the subclass,
    # and when you retrieve rows from the main class, you get instances
    # of the subclasses (if the rows should use the subclasses's class).
    #
    # By default, the plugin assumes that the +sti_key+ column (the first
    # argument to the plugin) holds the class name as a string.  However,
    # you can override this by using the <tt>:model_map</tt> option and/or
    # the <tt>:key_map</tt> option.
    #   
    # You should only load this plugin in the parent class, not in the subclasses.
    #   
    # You shouldn't call set_dataset in the model after applying this
    # plugin, otherwise subclasses might use the wrong dataset. You should
    # make sure this plugin is loaded before the subclasses. Note that since you
    # need to load the plugin before the subclasses are created, you can't use
    # direct class references in the plugin class.  You should specify subclasses
    # in the plugin call using class name strings or symbols, see usage below.
    #   
    # The filters and row_proc that sti_key sets up in subclasses may not work correctly if
    # those subclasses have further subclasses.  For those middle subclasses,
    # you may need to call set_dataset manually with the correct filter and
    # row_proc.
    # 
    # Usage:
    #
    #   # Use the default of storing the class name in the sti_key
    #   # column (:kind in this case)
    #   Employee.plugin :single_table_inheritance, :kind
    #
    #   # Using integers to store the class type, with a :model_map hash
    #   # and an sti_key of :type
    #   Employee.plugin :single_table_inheritance, :type,
    #     :model_map=>{1=>:Staff, 2=>:Manager}
    #
    #   # Using non-class name strings
    #   Employee.plugin :single_table_inheritance, :type,
    #     :model_map=>{'line staff'=>:Staff, 'supervisor'=>:Manager}
    #
    #   # Using custom procs, with :model_map taking column values
    #   # and yielding either a class, string, symbol, or nil, 
    #   # and :key_map taking a class object and returning the column
    #   # value to use
    #   Employee.plugin :single_table_inheritance, :type,
    #     :model_map=>proc{|v| v.reverse},
    #     :key_map=>proc{|klass| klass.name.reverse}
    #
    # One minor issue to note is that if you specify the <tt>:key_map</tt>
    # option as a hash, instead of having it inferred from the <tt>:model_map</tt>,
    # you should only use class name strings as keys, you should not use symbols
    # as keys.
    module SingleTableInheritance
      # Setup the necessary STI variables, see the module RDoc for SingleTableInheritance
      def self.configure(model, key, opts={})
        model.instance_eval do
          @sti_key = key 
          @sti_dataset = dataset
          @sti_model_map = opts[:model_map] || lambda{|v| v if v && v != ''}
          @sti_key_map = if km = opts[:key_map]
            if km.is_a?(Hash)
              h = Hash.new{|h,k| h[k.to_s] unless k.is_a?(String)}
              h.merge!(km)
            else
              km
            end
          elsif sti_model_map.is_a?(Hash)
            h = Hash.new{|h,k| h[k.to_s] unless k.is_a?(String)}
            sti_model_map.each do |k,v|
              h[v.to_s] = k
            end
            h
          else
            lambda{|klass| klass.name.to_s}
          end
          dataset.row_proc = lambda{|r| model.sti_load(r)}
        end
      end

      module ClassMethods
        # The base dataset for STI, to which filters are added to get
        # only the models for the specific STI subclass.
        attr_reader :sti_dataset

        # The column name holding the STI key for this model
        attr_reader :sti_key

        # A hash/proc with class keys and column value values, mapping
        # the the class to a particular value given to the sti_key column.
        # Used to set the column value when creating objects, and for the
        # filter when retrieving objects in subclasses.
        attr_reader :sti_key_map

        # A hash/proc with column value keys and class values, mapping
        # the value of the sti_key column to the appropriate class to use.
        attr_reader :sti_model_map

        # Copy the necessary attributes to the subclasses, and filter the
        # subclass's dataset based on the sti_kep_map entry for the class.
        def inherited(subclass)
          super
          sk = sti_key
          sd = sti_dataset
          skm = sti_key_map
          smm = sti_model_map
          subclass.set_dataset(sd.filter(SQL::QualifiedIdentifier.new(table_name, sk)=>skm[subclass]), :inherited=>true)
          subclass.instance_eval do
            @sti_key = sk
            @sti_dataset = sd
            @sti_key_map = skm
            @sti_model_map = smm
            @simple_table = nil
          end
        end

        # Return an instance of the class specified by sti_key,
        # used by the row_proc.
        def sti_load(r)
          sti_class(sti_model_map[r[sti_key]]).load(r)
        end

        private

        # Return a class object.  If a class is given, return it directly.
        # Treat strings and symbols as class names.  If nil is given or
        # an invalid class name string or symbol is used, return self.
        # Raise an error for other types.
        def sti_class(v)
          case v
          when String, Symbol
            constantize(v) rescue self
          when nil
            self
          when Class
            v
          else
            raise(Error, "Invalid class type used: #{v.inspect}")
          end
        end
      end

      module InstanceMethods
        # Set the sti_key column based on the sti_key_map.
        def before_create
          send("#{model.sti_key}=", model.sti_key_map[model]) unless send(model.sti_key)
          super
        end
      end
    end
  end
end
