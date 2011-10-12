require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

require 'time'
require 'securerandom'

class Buzzdata
  describe Buzzdata do
    GENERIC_USER = 'eviltrout'
    NONEXISTENT_USER = 'missing'
    USER_WITH_PRIVATE_DATASET = 'jpmckinney'
    PUBLISH_SLEEP_INTERVAL = 5

    CLONABLE_DATASET = 'eviltrout/pets'
    NONEXISTENT_DATASET = 'missing/missing'
    PRIVATE_DATASET_BELONGING_TO_ANOTHER_USER = 'jpmckinney/private'
    UNPUBLISHED_DATASET_BELONGING_TO_ANOTHER_USER = 'jpmckinney/unpublished'

    def fixture_path(basename)
      File.expand_path File.dirname(__FILE__) + '/fixtures/' + basename
    end

    describe '#initialize' do
      it 'should use custom configuration file' do
        client = Buzzdata.new nil, :config_file => fixture_path('custom.yml')
        client.instance_variable_get('@api_key').should == 'dummy'
      end

      it "should not raise an error if an API key is provided" do
        expect{Buzzdata.new 'dummy'}.not_to raise_error(Buzzdata::Error)
      end

      it "should raise an error if the configuration file is default and missing" do
        expect{Buzzdata.new}.to raise_error(Buzzdata::Error, /No API key provided/)
      end

      it "should raise an error if the configuration file is custom and missing" do
        expect{Buzzdata.new nil, :config_file => fixture_path('non_existent.yml')}.to raise_error(Buzzdata::Error, /No such file or directory/)
      end

      it "should raise an error if the configuration file is unreadable" do
        File.open(fixture_path('unreadable.yml'), 'w').chmod(0000) unless File.exist? fixture_path('unreadable.yml')
        expect{Buzzdata.new nil, :config_file => fixture_path('unreadable.yml')}.to raise_error(Buzzdata::Error, /Permission denied/)
      end

      it "should raise an error if the configuration file is invalid YAML" do
        expect{Buzzdata.new nil, :config_file => fixture_path('invalid_yaml.yml')}.to raise_error(Buzzdata::Error, /invalid YAML/)
      end

      it "should raise an error if the configuration file is not a Hash" do
        expect{Buzzdata.new nil, :config_file => fixture_path('not_a_hash.yml')}.to raise_error(Buzzdata::Error, /not a Hash/)
      end

      it "should raise an error if the API key is missing from the configuration file" do
        expect{Buzzdata.new nil, :config_file => fixture_path('missing_api_key.yml')}.to raise_error(Buzzdata::Error, /API key missing/)
      end
    end

    context 'with api key' do
      def create_dataset(attributes = {})
        dataset = @client.create_dataset create_attributes(attributes)
        if @to_delete and dataset['created_at']
          @to_delete << dataset['shortname']
        end
        dataset
      end

      def create_and_publish_dataset(attributes = {})
        dataset = create_dataset attributes
        upload = @client.start_upload dataset['id'], File.new(fixture_path('data.csv'))
        sleep 1 while upload.in_progress?
        sleep PUBLISH_SLEEP_INTERVAL
        if upload.success?
          @client.publish_dataset dataset['id']
        else
          raise upload.status_message
        end
      end

      def clone_dataset(id)
        dataset = @client.clone_dataset id
        if @to_delete and dataset['created_at']
          @to_delete << dataset['shortname']
        end
        dataset
      end

      def create_attributes(attributes = {})
        {
          :username => @username,
          :name     => SecureRandom.hex,
          :readme   => 'Hello World',
          :license  => 'cc0',
          :topics   => ['testing-buzzdata'],
        }.merge attributes
      end

      def stringify_keys(hash)
        hash.each_with_object({}){|(key,value),hash| hash[key.to_s] = value}
      end

      before(:each) do
        begin
          @client = Buzzdata.new nil, :config_file => 'config/test.yml'
          @username = YAML.load_file('config/test.yml')['username']
        rescue Buzzdata::Error
          raise "To run tests, you must create a config/test.yml YAML file with api_key and username keys. This user should not have any datasets."
        end
      end

      describe '#delete_dataset' do
        it 'should delete a dataset' do
          dataset = create_dataset
          response = @client.delete_dataset dataset['id']

          response.keys.should have(2).items
          response['id'].should == dataset['id']
          response['deleted'].should == true
        end

        it 'should raise an error if dataset is nonexistent' do
          expect{@client.delete_dataset NONEXISTENT_DATASET}.to raise_error(Buzzdata::Error, 'That dataset could not be found')
        end

        it 'should raise an error if dataset belongs to another user' do
          expect{@client.delete_dataset CLONABLE_DATASET}.to raise_error(Buzzdata::Error, "You don't have permission to do that")
        end
      end

      context 'with autodeletion' do
        before(:each) do
          @to_delete = []
        end

        after(:each) do
          @to_delete.each do |shortname|
            @client.delete_dataset "#{@username}/#{shortname}"
          end
        end
        
        describe '#create_dataset' do
          it 'should create a dataset' do
            attributes = create_attributes :name => 'foobar'
            response = create_dataset attributes

            dataset = stringify_keys(attributes).merge({
              'id' => "#{attributes[:username]}/#{attributes[:name]}",
              'shortname' => attributes[:name],
              'public' => true,
              'published' => false,
              'data_updated_at' => nil,
            })
            dataset.delete 'topics'

            response.keys.should have(10).items
            dataset.each do |key,value|
              response[key].should == value
            end
            Time.parse(response['created_at']).should be_within(5).of(Time.now)
          end

          it 'should create a public dataset' do
            [true, 1, nil].each do |value|
              dataset = create_dataset :public => value
              dataset['public'].should == true
            end
          end

          it 'should create a private dataset' do
            [false, 0, 42, 'string'].each do |value|
              dataset = create_dataset :public => value
              dataset['public'].should == false
            end
          end

          it 'should raise an error if attributes missing' do
            expect{@client.create_dataset nil}.to raise_error(Buzzdata::Error, 'Missing attributes')
          end

          it 'should raise an error if username is missing' do
            [nil, ''].each do |value|
              expect{create_dataset :username => value}.to raise_error(Buzzdata::Error, 'Username is required')
            end
          end

          it 'should raise an error if dataset name is missing' do
            [nil, ''].each do |value|
              expect{create_dataset :name => value}.to raise_error(Buzzdata::Error, 'Dataset name is required')
            end
            expect{create_dataset :name => ' '}.to raise_error(Buzzdata::Error, "Name can't be blank")
          end

          it 'should raise an error if dataset README is missing' do
            [nil, ''].each do |value|
              expect{create_dataset :readme => value}.to raise_error(Buzzdata::Error, 'Dataset readme is required')
            end
            expect{create_dataset :readme => ' '}.to raise_error(Buzzdata::Error, 'Missing parameter dataset[readme]')
          end

          it 'should raise an error if dataset license is missing' do
            [nil, ''].each do |value|
              expect{create_dataset :license => value}.to raise_error(Buzzdata::Error, 'Dataset license is required')
            end
            expect{create_dataset :license => ' '}.to raise_error(Buzzdata::Error, 'Missing parameter dataset[license]')
          end

          it 'should raise an error if dataset license is invalid' do
            expect{create_dataset :license => 'invalid'}.to raise_error(Buzzdata::Error, 'Invalid parameter dataset[license]')
          end

          it 'should raise an error if dataset topics are missing' do
            [nil, []].each do |value|
              expect{create_dataset :topics => value}.to raise_error(Buzzdata::Error, 'Dataset topics are required')
            end
            expect{create_dataset :topics => ' '}.to raise_error(Buzzdata::Error, 'Missing parameter dataset[topics]')
          end

          it 'should raise an error if dataset topic is invalid' do
            expect{create_dataset :topics => ['invalid']}.to raise_error(Buzzdata::Error, 'Invalid parameter dataset[topics]')
          end

          it 'should raise an error if dataset name is already taken' do
            dataset = create_dataset
            expect{create_dataset :name => dataset['name']}.to raise_error(Buzzdata::Error, 'Name has already been taken by one of your other datasets.')
          end

          it 'should raise an error if dataset shortname is already taken' do
            dataset = create_dataset :name => '<foo>'
            expect{create_dataset :name => 'foo'}.to raise_error(Buzzdata::Error, 'Name has already been taken by one of your other datasets.')
          end

          it 'should raise an error if dataset name is invalid' do
            expect{create_dataset :name => '!'}.to raise_error(Buzzdata::Error, 'Name requires at least 1 letter or number.')
          end
        end

        describe '#start_upload' do
          it 'should start an upload'
        end

        describe '#dataset_overview' do
          def get_and_validate(dataset)
            response = @client.dataset_overview dataset['id']

            response.keys.should have(10).items
            response.each do |key,value|
              dataset[key].should == value
            end
          end

          it 'should get the overview of a dataset' do
            dataset = create_and_publish_dataset
            get_and_validate dataset
          end

          it 'should raise an error if dataset is nonexistent' do
            expect{@client.dataset_overview NONEXISTENT_DATASET}.to raise_error(Buzzdata::Error, 'That dataset could not be found')
          end

          it 'should get the overview of a dataset if it belongs to user and is unpublished' do
            dataset = create_dataset
            get_and_validate dataset
          end

          it 'should get the overview of a dataset if it belongs to user and is private' do
            dataset = create_and_publish_dataset :public => false
            get_and_validate dataset
          end

          it 'should raise an error if dataset belongs to another user and is unpublished' do
            expect{@client.dataset_overview UNPUBLISHED_DATASET_BELONGING_TO_ANOTHER_USER}.to raise_error(Buzzdata::Error, "You don't have permission to do that")
          end

          it 'should raise an error if dataset belongs to another user and is private' do
            expect{@client.dataset_overview PRIVATE_DATASET_BELONGING_TO_ANOTHER_USER}.to raise_error(Buzzdata::Error, "You don't have permission to do that")
          end
        end

        describe '#dataset_history' do
          it 'should get the history of a dataset' do
            dataset = create_and_publish_dataset
            response = @client.dataset_history dataset['id']

            response.should have(1).item
            response.each do |x|
              x.should have(3).items
              x['version'].should == 0
              x['created_at'].should == dataset['created_at']
              x['username'].should == dataset['username']
            end
          end

          it 'should raise an error if dataset is nonexistent' do
            expect{@client.dataset_history NONEXISTENT_DATASET}.to raise_error(Buzzdata::Error, 'That dataset could not be found')
          end

          it 'should get the history of a dataset if it belongs to user and is unpublished' do
            dataset = create_dataset
            @client.dataset_history(dataset['id']).should be_empty
          end

          it 'should get the history of a dataset if it belongs to user and is private' do
            dataset = create_and_publish_dataset :public => false
            @client.dataset_history(dataset['id']).should have(1).item
          end

          it 'should raise an error if dataset belongs to another user and is unpublished' do
            expect{@client.dataset_history UNPUBLISHED_DATASET_BELONGING_TO_ANOTHER_USER}.to raise_error(Buzzdata::Error, "You don't have permission to do that")
          end

          it 'should raise an error if dataset belongs to another user and is private' do
            expect{@client.dataset_history PRIVATE_DATASET_BELONGING_TO_ANOTHER_USER}.to raise_error(Buzzdata::Error, "You don't have permission to do that")
          end
        end

        describe '#publish_dataset' do
          it 'should publish a dataset' do
            dataset = create_dataset
            upload = @client.start_upload dataset['id'], File.new(fixture_path('data.csv'))
            sleep 1 while upload.in_progress?
            sleep PUBLISH_SLEEP_INTERVAL
            response = @client.publish_dataset dataset['id']

            dataset['published'] = true
            dataset.delete 'created_at' # XXX this is unusual

            response.keys.should have(10).items
            dataset.each do |key,value|
              response[key].should == value
            end
          end

          it 'should raise an error if no data uploaded' do
            dataset = create_dataset
            sleep PUBLISH_SLEEP_INTERVAL
            expect{@client.publish_dataset dataset['id']}.to raise_error(Buzzdata::Error, "You don't have permission to do that")
          end

          it 'should raise an error if dataset is already published' do
            dataset = create_and_publish_dataset
            sleep PUBLISH_SLEEP_INTERVAL
            response = @client.publish_dataset dataset['id']

            # XXX this is unusual: check that values are identical
            dataset.each do |key,value|
              response[key].should == value
            end
          end

          it 'should raise an error if dataset is nonexistent' do
            expect{@client.publish_dataset NONEXISTENT_DATASET}.to raise_error(Buzzdata::Error, 'That dataset could not be found')
          end

          it 'should raise an error if dataset belongs to another user' do
            expect{@client.publish_dataset UNPUBLISHED_DATASET_BELONGING_TO_ANOTHER_USER}.to raise_error(Buzzdata::Error, "You don't have permission to do that")
          end
        end

        describe '#clone_dataset' do
          it 'should clone a dataset' do
            dataset = @client.dataset_overview CLONABLE_DATASET
            response = clone_dataset dataset['id']

            dataset['id'] = "#{@username}/#{dataset['shortname']}"
            dataset['username'] = @username
            dataset['license'] = nil
            dataset['data_updated_at'] = nil
            dataset.delete 'created_at' # XXX this is unusual

            response.keys.should have(10).items
            dataset.each do |key,value|
              response[key].should == value
            end
            Time.parse(response['created_at']).should be_within(5).of(Time.now)
          end

          it 'should raise an error if dataset is unpublished' do
            dataset = create_dataset
            expect{clone_dataset dataset['id']}.to raise_error(Buzzdata::Error, "You don't have permission to do that")
          end

          it 'should raise an error if dataset is nonexistent' do
            expect{clone_dataset NONEXISTENT_DATASET}.to raise_error(Buzzdata::Error, 'That dataset could not be found')
          end

          it 'should raise an error if dataset is already cloned' do
            dataset = clone_dataset CLONABLE_DATASET
            expect{clone_dataset CLONABLE_DATASET}.to raise_error(Buzzdata::Error, 'Name has already been taken by one of your other datasets.')
          end

          it 'should raise an error if dataset belongs to user' do
            dataset = create_and_publish_dataset
            expect{clone_dataset dataset['id']}.to raise_error(Buzzdata::Error, "You don't have permission to do that")
          end

          it 'should raise an error if dataset belongs to another user and is unpublished' do
            expect{clone_dataset UNPUBLISHED_DATASET_BELONGING_TO_ANOTHER_USER}.to raise_error(Buzzdata::Error, "You don't have permission to do that")
          end

          it 'should raise an error if dataset belongs to another user and is private' do
            expect{clone_dataset PRIVATE_DATASET_BELONGING_TO_ANOTHER_USER}.to raise_error(Buzzdata::Error, "You don't have permission to do that")
          end
        end

        describe '#licenses' do
          it 'should get a list of licenses' do
            licenses = @client.licenses
            licenses.should be_an Array
            licenses.each do |license|
              license.should have_key 'id'
            end
          end
        end

        describe '#topics' do
          it 'should get a list of topics' do
            topics = @client.topics
            topics.should be_an Array
            topics.each do |topic|
              topic.should have_key 'id'
              topic.should have_key 'name'
            end
          end
        end

        describe '#search' do
          it 'should search BuzzData' do
            response = @client.search 'buzzdata'
            response.should have_at_least(1).item
            response.each do |x|
              %w(label value id url type).each do |key|
                x.should have_key(key)
              end
            end
          end
        end

        describe '#datasets_list' do
          it 'should list datasets' do
            dataset = create_and_publish_dataset
            response = @client.datasets_list @username

            response.should have(1).item
            response.each do |x|
              x.keys.should have(5).items
              x.each do |key,value|
                dataset[key].should == value
              end
            end
          end

          it 'should raise an error if user is nonexistent' do
            expect{@client.datasets_list NONEXISTENT_USER}.to raise_error(Buzzdata::Error, 'That dataset could not be found')
          end

          it 'should list a dataset if it belongs to user and is unpublished' do
            dataset = create_dataset
            @client.datasets_list(@username).should have(1).item
          end

          it 'should list a dataset if it belongs to user and is private' do
            dataset = create_and_publish_dataset :public => false
            @client.datasets_list(@username).should have(1).item
          end

          it 'should not list private datasets if they belong to another user' do
            response = @client.datasets_list USER_WITH_PRIVATE_DATASET
            response.map{|dataset| dataset['id']}.should_not include PRIVATE_DATASET_BELONGING_TO_ANOTHER_USER
          end
        end

        describe '#download_data' do
          it 'should download a dataset' do
            dataset = create_and_publish_dataset
            response = @client.download_data dataset['id']
            response.should == File.read(fixture_path('data.csv'))
          end

          it 'should raise an error if dataset is unpublished' do
            dataset = create_dataset
            expect{@client.download_data dataset['id']}.to raise_error(StandardError, /No dataset could be found for/)
          end

          it 'should raise an error if dataset is nonexistent' do
            expect{@client.download_data NONEXISTENT_DATASET}.to raise_error(Buzzdata::Error, 'That dataset could not be found')
          end

          it 'should download a dataset if it belongs to user and is private' do
            dataset = create_and_publish_dataset :public => false
            response = @client.download_data dataset['id']
            response.should == File.read(fixture_path('data.csv'))
          end

          it 'should raise an error if dataset belongs to another user and is private' do
            expect{@client.download_data PRIVATE_DATASET_BELONGING_TO_ANOTHER_USER}.to raise_error(Buzzdata::Error, "You don't have permission to do that")
          end
        end

        describe '#user_info' do
          it 'should get user info' do
            response = @client.user_info GENERIC_USER

            response.keys.should have(5).items
            response['id'].should == GENERIC_USER
          end

          it 'should raise an error if user is nonexistent' do
            expect{@client.user_info NONEXISTENT_USER}.to raise_error(Buzzdata::Error, '')
          end
        end
      end
    end
  end
end
