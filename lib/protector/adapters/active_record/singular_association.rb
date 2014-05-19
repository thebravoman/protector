module Protector
  module Adapters
    module ActiveRecord
      # Patches `ActiveRecord::Associations::SingularAssociation`
      module SingularAssociation
        extend ActiveSupport::Concern

        included do
          alias_method_chain :reader, :protector
        end

        # Reader has to be explicitly overrided for cases when the
        # loaded association is cached
        def reader_with_protector(*args)
          return reader_without_protector(*args) unless protector_subject?
          with_unprotected_scope do |subject|
            reader_without_protector(*args).try :restrict!, subject
          end
        end

        # Forwards protection subject to the new instance
        def build_record_with_protector(*args)
          return build_record_without_protector(*args) unless protector_subject?
          build_record_without_protector(*args).restrict!(protector_subject)
        end

        private

        def with_unprotected_scope
          cached_subject = protector_subject
          unrestrict! if Protector.config.unprotect_singular_scope?
          value = yield(cached_subject)
          restrict!(cached_subject)
          value
        end
      end
    end
  end
end
