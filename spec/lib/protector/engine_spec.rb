require 'spec_helpers/boot'

if defined?(Rails)
  describe Protector::Engine do
    before(:all) do
      Combustion.initialize! :active_record do
        config.protector.paranoid = true
        config.action_controller.action_on_unpermitted_parameters = :raise
      end

      Protector.activate!

      unless Protector::Adapters::ActiveRecord.modern?
        ActiveRecord::Base.send(:include, ActiveModel::ForbiddenAttributesProtection)
        ActiveRecord::Base.send(:include, Protector::ActiveRecord::Adapters::StrongParameters)
      end
    end

    after(:all) do
      Protector.config.paranoid = false
    end

  	it "inherits Rails config" do
      Protector.config.paranoid?.should == true
      Protector.config.strong_parameters?.should == true
    end

    describe "strong_parameters" do
      before(:all) do
        load 'migrations/active_record.rb'

        module FluffyExt
          extend ActiveSupport::Concern

          included do
            protect do
              can :create, :string
              can :update, :number
            end
          end
        end

        Fluffy.send(:include, FluffyExt)
      end

      let(:dummy) do
        Class.new(ActiveRecord::Base) do
          def self.model_name; ActiveModel::Name.new(self, nil, "dummy"); end
          def self.name; 'Dummy'; end
          self.table_name = "dummies"

          has_many :fluffies
          accepts_nested_attributes_for :fluffies

          protect do
            can :create, :string
            can :update, :number
          end
        end
      end

      def params(*args)
        ActionController::Parameters.new *args
      end

      it "creates" do
        expect{ dummy.restrict!.new params(string: 'test') }.to_not raise_error
        expect{ dummy.restrict!.create(params(string: 'test')).delete }.to_not raise_error
        expect{ dummy.restrict!.create!(params(string: 'test')).delete }.to_not raise_error
        expect{ dummy.restrict!.new params(number: 1) }.to raise_error
      end

      it "updates" do
        instance = dummy.create!

        expect{ instance.restrict!.assign_attributes params(string: 'test') }.to raise_error
        expect{ instance.restrict!.assign_attributes params(number: 1) }.to_not raise_error
      end

      it 'creates with nested attributes' do
        expect{ dummy.restrict!.new params(string: 'test',
                                           fluffies_attributes: [{string: 'test'}]) }.to_not raise_error
        expect{ dummy.restrict!.new params(string: 'test',
                                           fluffies_attributes: [{number: 1}]) }.to raise_error
      end
    end
  end
end