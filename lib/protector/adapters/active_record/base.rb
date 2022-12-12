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

            if primary_key == name || Array(primary_key).include?(name)
              # this is the super implemenation of lib/active_record/attribute_methods/read.rb
              # as of Rails 7.0.4
              # https://github.com/rails/rails/blob/f6a8cb42d8a61753efa658c809c5e1673426eb10/activerecord/lib/active_record/attribute_methods/read.rb
              # The api for owner is not public. We know.
              # There seems to be no public API for this.
              ActiveModel::AttributeMethods::AttrNames.define_attribute_accessor_method(
                owner, name
              ) do |temp_method_name, attr_name_expr|
                owner.define_cached_method(name, as: temp_method_name, namespace: :active_record) do |batch|
                  batch <<
                    "def #{temp_method_name}" <<
                    "  _read_attribute(#{attr_name_expr}) { |n| missing_attribute(n, caller) }" <<
                    "end"
                end
              end
            else
              # plug in the protector to read only if readable or unprotected.
              ActiveModel::AttributeMethods::AttrNames.define_attribute_accessor_method(
                owner, name
              ) do |temp_method_name, attr_name_expr|
                owner.define_cached_method(name, as: temp_method_name, namespace: :active_record) do |batch|
                  batch <<
                    "def #{temp_method_name}" <<
                    "  if !protector_subject? || protector_meta.readable?(#{temp_method_name.inspect})" <<
                    "    _read_attribute(#{attr_name_expr}) { |n| missing_attribute(n, caller) }" <<
                    "  else" <<
                    "    nil" <<
                    "  end" <<
                    "end"
                end
              end
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
