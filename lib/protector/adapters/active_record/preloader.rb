module Protector
  module Adapters
    module ActiveRecord
      # Patches `ActiveRecord::Associations::Preloader`
      module Preloader
        extend ActiveSupport::Concern
        # Patches `ActiveRecord::Associations::Preloader::Association`
        module Association
          extend ActiveSupport::Concern
          included do
            alias_method :scope_without_protector, :scope
            alias_method :scope, :scope_with_protector
          end

          # Gets current subject of preloading association
          def protector_subject
            # Owners are always loaded from the single source
            # having same protector_subject
            owners.first.protector_subject
          end

          def protector_subject?
            owners.first.protector_subject?
          end

          # Restricts preloading association scope with subject of the owner
          def scope_with_protector(*_args)
            return scope_without_protector unless protector_subject?

            @meta ||= klass.protector_meta.evaluate(protector_subject)
            
            # There is a difference between AR 4.2 and AR 5.0
            # In 4.2 the spawn_methods.rb is 
            # [28, 37] in /Users/kireto/.rvm/gems/ruby-2.7.6@callpixels/gems/activerecord-4.2.11.21/lib/active_record/relation/spawn_methods.rb
            #    28:     #
            #    29:     # This is mainly intended for sharing common conditions between multiple associations.
            #    30:     def merge(other)
            #    31:       if other.is_a?(Array)
            #    32:         to_a & other
            # => 33:       elsif other
            #    34:         spawn.merge!(other)
            #    35:       else
            #    36:         self
            #    37:       end
            # 
            # and we can see that if we pass 'false' we will return self.
            # 
            # But this is not true for 5.0 where if we pass 'false' we will raise and error
            # 
            # [28, 37] in /Users/kireto/.rvm/gems/ruby-2.7.6@callpixels/gems/activerecord-5.0.7.2/lib/active_record/relation/spawn_methods.rb
            #    28:     #
            #    29:     # This is mainly intended for sharing common conditions between multiple associations.
            #    30:     def merge(other)
            #    31:       if other.is_a?(Array)
            #    32:         records & other
            # => 33:       elsif other
            #    34:         spawn.merge!(other)
            #    35:       else
            #    36:         raise ArgumentError, "invalid argument: #{other.inspect}."
            #    37:       end
            # 
            # To continue to support AR 4.2 case we are not merging if the relation is false
            # 
            # The original code was just a call to 
            # scope_without_protector.merge(@meta.relation)
            # 
            # We could further investigate if the case of @meta.relation eq to false
            # is correct and if it should even get to here. 
            if @meta.relation != false
              scope_without_protector.merge(@meta.relation)
            else
              scope_without_protector
            end
          end
        end
      end
    end
  end
end
