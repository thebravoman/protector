module Protector
  module Adapters
    module ActiveRecord
      # Patches `ActiveRecord::Base`
      module Base
        extend ActiveSupport::Concern

        included do
          include Protector::DSL::Base
          include Protector::DSL::Entry

          before_destroy :protector_ensure_destroyable

          # We need this to make sure no ActiveRecord classes managed
          # to cache db scheme and create corresponding methods since
          # we want to modify the way they get created
          ObjectSpace.each_object(Class).each do |klass|
            klass.undefine_attribute_methods if klass < self
          end

          # Drops {Protector::DSL::Meta::Box} cache when subject changes
          def restrict!(*args)
            @protector_meta = nil
            super
          end

          if !Protector::Adapters::ActiveRecord.modern?
            def self.restrict!(*args)
              scoped.restrict!(*args)
            end
          else
            def self.restrict!(*args)
              all.restrict!(*args)
            end
          end

          alias :original_read_attribute :read_attribute

          def [](name)
            # rubocop:disable ParenthesesAroundCondition
            if !protector_subject? ||
                name == self.class.primary_key ||
                (self.class.primary_key.is_a?(Array) && self.class.primary_key.include?(name)) ||
                protector_meta.readable?(name)

              original_read_attribute(name)
            else
              nil
            end
            # rubocop:enable ParenthesesAroundCondition
          end

          def read_attribute(name)
            Protector.config.protect_read_attribute? ? self[name] : original_read_attribute(name)
          end

          def association(*params)
            return super unless protector_subject?
            super.restrict!(protector_subject)
          end
        end

        module ClassMethods
          # Storage of {Protector::DSL::Meta}
          def protector_meta
            ensure_protector_meta!(Protector::Adapters::ActiveRecord) do
              column_names
            end
          end

          # Wraps every `.field` method with a check against {Protector::DSL::Meta::Box#readable?}
          def define_method_attribute(name, owner: )
            super

            # Show some <3 to composite primary keys
            unless primary_key == name || Array(primary_key).include?(name)
              # This follows the way rails generates methods in https://github.com/rails/rails/pull/39098
              owner <<
                "alias_method #{"#{name}_unprotected".inspect}, #{name.inspect}" <<
                "def #{name}" <<
                "  if !protector_subject? || protector_meta.readable?(#{name.inspect})" <<
                "    #{name}_unprotected" <<
                "  else" <<
                "    nil" <<
                "  end" <<
                "end"
            end
          end
        end

        # Gathers real changed values bypassing restrictions
        def protector_changed
          HashWithIndifferentAccess[changed.map { |field| [field, read_attribute(field)] }]
        end

        # Storage for {Protector::DSL::Meta::Box}
        def protector_meta(subject=protector_subject)
          @protector_meta ||= self.class.protector_meta.evaluate(subject, self)
        end

        # Checks if current model can be selected in the context of current subject
        def visible?
          return true unless protector_meta.scoped?

          protector_meta.relation.where(
            self.class.primary_key => id
          ).any?
        end

        # Checks if current model can be created in the context of current subject
        def creatable?
          protector_meta.creatable? protector_changed
        end

        # Checks if current model can be updated in the context of current subject
        def updatable?
          protector_meta.updatable? protector_changed
        end

        # Checks if current model can be destroyed in the context of current subject
        def destroyable?
          protector_meta.destroyable?
        end

        def can?(action, field=false)
          protector_meta.can?(action, field)
        end

        private
        def protector_ensure_destroyable
          return true unless protector_subject?
          destroyable?
        end
      end
    end
  end
end
