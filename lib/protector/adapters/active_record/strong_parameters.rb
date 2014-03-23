module Protector
  module ActiveRecord
    module Adapters
      module StrongParameters
        class << self
          def sanitize!(args, is_new, meta)
            return if args[0].permitted?

            if is_new
              args[0] = args[0].permit(*with_nested_permissions(meta, :create)) if meta.access.include? :create
            else
              args[0] = args[0].permit(*with_nested_permissions(meta, :update)) if meta.access.include? :update
            end
          end

          private

          def with_nested_permissions(meta, access_level)
            if meta.can?(access_level)
              (meta.access[access_level] || {}).keys + nested_permissions(meta, access_level)
            else
              []
            end
          end

          def nested_permissions(meta, access_level)
            meta.model.nested_attributes_options.map do |model_name, perms|
              nested_model = model_name.to_s.classify.constantize

              attributes = with_nested_permissions(nested_model.protector_meta.evaluate(meta.subject), access_level)
              attributes << '_destroy' if perms[:allow_destroy]

              {"#{model_name}_attributes".to_sym => attributes}
            end
          end
        end

        # strong_parameters integration
        def sanitize_for_mass_assignment(*args)
          # We check only for updation here since the creation will be handled by relation
          # (see Protector::Adapters::ActiveRecord::Relation#new_with_protector and
          # Protector::Adapters::ActiveRecord::Relation#create_with_protector)
          if Protector.config.strong_parameters? && args.first.respond_to?(:permit) \
              && !new_record? && protector_subject?

            StrongParameters.sanitize! args, false, protector_meta
          end

          super
        end
      end
    end
  end
end
