# frozen_string_literal: true

require_relative "../path"
include Spec::Path

$LOAD_PATH.unshift(*Dir[Spec::Path.base_system_gems.join("gems/{artifice,mustermann,rack,tilt,sinatra,ruby2_keywords}-*/lib")].map(&:to_s))

require "artifice"
require "sinatra/base"

ALL_REQUESTS = [] # rubocop:disable Style/MutableConstant
ALL_REQUESTS_MUTEX = Mutex.new

at_exit do
  if expected = ENV["BUNDLER_SPEC_ALL_REQUESTS"]
    expected = expected.split("\n").sort
    actual = ALL_REQUESTS.sort

    unless expected == actual
      raise "Unexpected requests!\nExpected:\n\t#{expected.join("\n\t")}\n\nActual:\n\t#{actual.join("\n\t")}"
    end
  end
end

class Endpoint < Sinatra::Base
  def self.all_requests
    @all_requests ||= []
  end

  GEM_REPO = Pathname.new(ENV["BUNDLER_SPEC_GEM_REPO"] || Spec::Path.gem_repo1)
  set :raise_errors, true
  set :show_exceptions, false

  def call!(*)
    super.tap do
      ALL_REQUESTS_MUTEX.synchronize do
        ALL_REQUESTS << @request.url
      end
    end
  end

  helpers do
    def dependencies_for(gem_names, gem_repo = GEM_REPO)
      return [] if gem_names.nil? || gem_names.empty?

      all_specs = %w[specs.4.8 prerelease_specs.4.8].map do |filename|
        Marshal.load(File.open(gem_repo.join(filename)).read)
      end.inject(:+)

      all_specs.map do |name, version, platform|
        spec = load_spec(name, version, platform, gem_repo)
        next unless gem_names.include?(spec.name)
        {
          :name         => spec.name,
          :number       => spec.version.version,
          :platform     => spec.platform.to_s,
          :dependencies => spec.dependencies.select {|dep| dep.type == :runtime }.map do |dep|
            [dep.name, dep.requirement.requirements.map {|a| a.join(" ") }.join(", ")]
          end,
        }
      end.compact
    end

    def load_spec(name, version, platform, gem_repo)
      full_name = "#{name}-#{version}"
      full_name += "-#{platform}" if platform != "ruby"
      Marshal.load(Bundler.rubygems.inflate(File.binread(gem_repo.join("quick/Marshal.4.8/#{full_name}.gemspec.rz"))))
    end
  end

  get "/quick/Marshal.4.8/:id" do
    redirect "/fetch/actual/gem/#{params[:id]}"
  end

  get "/fetch/actual/gem/:id" do
    File.binread("#{GEM_REPO}/quick/Marshal.4.8/#{params[:id]}")
  end

  get "/gems/:id" do
    File.binread("#{GEM_REPO}/gems/#{params[:id]}")
  end

  get "/api/v1/dependencies" do
    Marshal.dump(dependencies_for(params[:gems]))
  end

  get "/specs.4.8.gz" do
    File.binread("#{GEM_REPO}/specs.4.8.gz")
  end

  get "/prerelease_specs.4.8.gz" do
    File.binread("#{GEM_REPO}/prerelease_specs.4.8.gz")
  end
end

Artifice.activate_with(Endpoint)
