require 'spec_helper'

describe Metasploit::Concern::Loader do
  shared_context 'Metasploit::Concern::ModuleWithConcerns' do
    #
    # Methods
    #

    def remove_load_hooks
      load_hooks = ActiveSupport.instance_variable_get :@load_hooks
      load_hooks.delete(:metasploit_concern_module_with_concerns)

      loaded = ActiveSupport.instance_variable_get :@loaded
      loaded.delete(:metasploit_concern_module_with_concerns)
    end

    #
    # lets
    #

    let(:module_pathname) do
      root.join('metasploit', 'concern', 'module_with_concerns')
    end

    #
    # Callbacks
    #

    before(:all) do
      remove_load_hooks
    end

    after(:each) do
      remove_load_hooks
    end
  end

  shared_context 'Metasploit::Concern::ModuleWithConcerns::ConcernForModule' do
    include_context 'Metasploit::Concern::ModuleWithConcerns'

    #
    # lets
    #

    let(:concern_name) do
      "Metasploit::Concern::ModuleWithConcerns::#{concern_relative_name}"
    end

    let(:concern_relative_name) do
      'ConcernForModule'
    end

    let(:concern_pathname) do
      module_pathname.join("#{concern_relative_name.underscore}.rb")
    end

    #
    # Callbacks
    #

    before(:each) do
      concern_pathname.parent.mkpath

      concern_pathname.open('w') do |f|
        f.puts "module #{concern_name}"
        f.puts 'end'
      end
    end

    after(:each) do
      ActiveSupport::Dependencies.clear
    end
  end

  subject(:loader) do
    described_class.new(root: root)
  end

  #
  # Methods
  #

  def remove_root
    return unless root.exist?
    root.rmtree
  end

  def root
    Metasploit::Concern::Engine.root.join('spec', 'tmp')
  end

  #
  # lets
  #

  let(:load_path) do
    root.to_path
  end

  #
  # Callbacks
  #

  # clean up interrupted run
  before(:all) do
    remove_root
  end

  around(:each) do |example|
    loaded_features_before = $LOADED_FEATURES.dup

    begin
      example.run
    ensure
      $LOADED_FEATURES.replace(loaded_features_before)
    end
  end

  around(:each) do |example|
    load_path_before = $LOAD_PATH.dup

    begin
      example.run
    ensure
      $LOAD_PATH.replace(load_path_before)
    end
  end

  around(:each) do |example|
    mechanism_before = ActiveSupport::Dependencies.mechanism

    begin
      example.run
    ensure
      ActiveSupport::Dependencies.mechanism = mechanism_before
    end
  end

  around(:each) do |example|
    autoload_paths_before = ActiveSupport::Dependencies.autoload_paths.dup

    begin
      example.run
    ensure
      ActiveSupport::Dependencies.autoload_paths = autoload_paths_before
    end
  end

  before(:each) do
    ActiveSupport::Dependencies.mechanism = :load
  end

  after(:each) do
    remove_root
  end

  context 'validations' do
    it { should validate_presence_of :root }
  end

  context '#constantize_pathname' do
    subject(:constantize_pathname) do
      loader.send(:constantize_pathname, mechanism: :constantize, pathname: descendant_pathname)
    end

    before(:each) do
      # add to load path so that constantize works
      $LOAD_PATH.unshift(load_path)
      ActiveSupport::Dependencies.autoload_paths << load_path
    end

    context 'with constant name' do
      include_context 'Metasploit::Concern::ModuleWithConcerns::ConcernForModule'

      let(:descendant_pathname) do
        concern_pathname
      end

      it 'returns constant' do
        expect(constantize_pathname).not_to be_nil
        # don't use constant name directly to ensure that the loader is resolving the constant and not the test
        expect(constantize_pathname.name).to eq(concern_name)
      end
    end

    context 'without constant_name' do
      include_context 'Metasploit::Concern::ModuleWithConcerns'

      let(:invalid_extension) do
        '.rb.bak'
      end

      let(:descendant_pathname) do
        module_pathname.join("concern_for_module#{invalid_extension}")
      end

      it { should be_nil }
    end
  end

  context '#each_pathname_constant' do
    include_context 'Metasploit::Concern::ModuleWithConcerns::ConcernForModule'

    #
    # Methods
    #

    def each_pathname_constant(&block)
      loader.each_pathname_constant(mechanism: :constantize, parent_pathname: module_pathname, &block)
    end

    #
    # Callbacks
    #

    before(:each) do
      # add to load path so that constantize works
      $LOAD_PATH.unshift(load_path)
      ActiveSupport::Dependencies.autoload_paths << load_path
    end

    it 'yields concerns' do
      concern_names = []

      each_pathname_constant do |constant|
        concern_names << constant.name
      end

      expect(concern_names).to match_array([concern_name])
    end
  end

  context '#glob' do
    subject(:glob) do
      loader.glob
    end

    it { should be_a Pathname }

    it 'is all .rb files under #root' do
      expect(glob).to eq(root.join('**', '*.rb'))
    end
  end

  context '#module_pathname_set' do
    subject(:module_pathname_set) do
      loader.module_pathname_set
    end

    let(:expected_module_pathnames) do
      Array.new(2) do |i|
        root.join('metasploit', 'concern', "module_with_concerns#{i}")
      end
    end

    let(:non_module_pathname) do
      root.join('metasploit', 'concern', 'module_without_concerns')
    end

    before(:each) do
      non_module_pathname.mkpath

      expected_module_pathnames.each do |expected_module_pathname|
        expected_module_pathname.mkpath
        concern_pathname = expected_module_pathname.join('concern_for_module.rb')

        concern_pathname.open('w') do |f|
          f.puts '# A concern'
        end
      end
    end

    it { should be_a Set }

    it 'includes directories under #root that have .rb files' do
      expected_module_pathnames.each do |expected_module_pathname|
        expect(module_pathname_set).to include(expected_module_pathname)
      end
    end

    it 'does not include directories without .rb files' do
      expect(module_pathname_set).not_to include(non_module_pathname)
    end
  end

  context '#pathname_to_constant_name' do
    subject(:pathname_to_constant_name) do
      loader.send(:pathname_to_constant_name, descendant_pathname)
    end

    context 'extension' do
      let(:descendant_pathname) do
        root.join('metasploit', 'concern', 'module_with_concerns', "concern_for_module#{extension}")
      end

      context 'with .rb' do
        let(:extension) do
          '.rb'
        end

        it 'returns a valid constant name' do
          expect(pathname_to_constant_name).to eq('Metasploit::Concern::ModuleWithConcerns::ConcernForModule')
        end
      end

      context 'without .rb' do
        let(:extension) do
          '.rb.bak'
        end

        it { should be_nil }
      end
    end
  end

  context '#register' do
    include_context 'Metasploit::Concern::ModuleWithConcerns::ConcernForModule'

    subject(:register) do
      loader.register
    end

    context 'with base class ActiveSupport::Dependencies.autoloaded?' do
      before(:each) do
        module_pathname.parent.mkpath

        open("#{module_pathname}.rb", 'w') do |f|
          f.puts "class Metasploit::Concern::ModuleWithConcerns"
          f.puts "  ActiveSupport.run_load_hooks(:metasploit_concern_module_with_concerns, self)"
          f.puts "end"
        end
      end

      before(:each) do
        $LOAD_PATH.unshift(load_path)
        ActiveSupport::Dependencies.autoload_paths << load_path
      end

      context 'false' do
        #
        # Callbacks
        #

        before(:each) do
          Metasploit::Concern.autoload :ModuleWithConcerns, 'metasploit/concern/module_with_concerns.rb'
        end

        after(:each) do
          Metasploit::Concern.send(:remove_const, :ModuleWithConcerns)
        end

        it 'has base class loaded' do
          expect do
            Metasploit::Concern::ModuleWithConcerns
          end.not_to raise_error

          expect(Metasploit::Concern::ModuleWithConcerns).to be_a Class
        end

        it 'includes concerns' do
          expect { register }.to change {
            Metasploit::Concern::ModuleWithConcerns.ancestors.map(&:name).include? concern_name
          }.to(true)
        end

        it 'does not end up with two copies of concern when reloaded' do
          register

          Metasploit::Concern::ModuleWithConcerns
          expect(Metasploit::Concern::ModuleWithConcerns.ancestors.map(&:name).count(concern_name)).to eq(1)

          expect { ActiveSupport::Dependencies.clear }.not_to change {
            Metasploit::Concern::ModuleWithConcerns.constants.include? concern_relative_name.to_sym
          }

          Metasploit::Concern::ModuleWithConcerns.send(
            :include,
            Metasploit::Concern::ModuleWithConcerns::ConcernForModule
          )

          expect(Metasploit::Concern::ModuleWithConcerns.ancestors.map(&:name).count(concern_name)).to eq(1)
        end
      end

      context 'true' do
        after(:each) do
          ActiveSupport::Dependencies.clear
        end

        it 'has base class loaded' do
          expect do
            Metasploit::Concern::ModuleWithConcerns
          end.not_to raise_error

          expect(Metasploit::Concern::ModuleWithConcerns).to be_a Class
        end

        it 'includes concerns' do
          expect { register }.to change {
            Metasploit::Concern::ModuleWithConcerns.ancestors.map(&:name).include? concern_name
          }.to(true)
        end

        it 'does not end up with two copies of concern when reloaded and included' do
          register

          Metasploit::Concern::ModuleWithConcerns
          expect(Metasploit::Concern::ModuleWithConcerns.ancestors.map(&:name).count(concern_name)).to eq(1)

          ActiveSupport::Dependencies.clear
          expect(Metasploit::Concern.constants).not_to include(:ModuleWithConcerns),
                                                       'Expected Metasploit::Concern::ModuleWithConcerns to be unloaded by ActiveSupport::Dependencies.clear'

          Metasploit::Concern::ModuleWithConcerns.send(
              :include,
              Metasploit::Concern::ModuleWithConcerns::ConcernForModule
          )

          expect(Metasploit::Concern::ModuleWithConcerns.ancestors.map(&:name).count(concern_name)).to eq(1)
        end
      end
    end

    # rspec run with Rails loaded for Rails::Engine, so no need to stub Rails
    context 'with Rails' do
      context 'with development' do
        #
        # lets
        #

        let(:env) do
          ActiveSupport::StringInquirer.new('development')
        end

        #
        # Callbacks
        #

        before(:each) do
          allow(Rails).to receive(:env).and_return(env)
        end

        after(:each) do
          ActiveSupport::Dependencies.explicitly_unloadable_constants.delete('Metasploit::Concern::ModuleWithConcerns')
        end

        it 'does not add module with concerns to unloadable constants because it would causes required classes to no be reloaded' do
          register

          expect(ActiveSupport::Dependencies.explicitly_unloadable_constants).not_to include('Metasploit::Concern::ModuleWithConcerns')
        end
      end

      # rspec run under test environment, so no need to stub Rails.env
      context 'without development' do
        it 'does not add module with concerns to unloadable constants' do
          register

          expect(ActiveSupport::Dependencies.explicitly_unloadable_constants).not_to include('Metasploit::Concern::ModuleWithConcerns')
        end
      end
    end
  end
end
