# frozen_string_literal: true

# `brew uses foo bar` returns formulae that use both foo and bar
# If you want the union, run the command twice and concatenate the results.
# The intersection is harder to achieve with shell tools.

require "formula"
require "cli/parser"

module Homebrew
  extend DependenciesHelpers

  module_function

  def uses_args
    Homebrew::CLI::Parser.new do
      usage_banner <<~EOS
        `uses` [<options>] <formula>

        Show formulae that specify <formula> as a dependency (i.e. show dependents
        of <formula>). When given multiple formula arguments, show the intersection
        of formulae that use <formula>. By default, `uses` shows all formulae that
        specify <formula> as a required or recommended dependency for their stable builds.
      EOS
      switch "--recursive",
             description: "Resolve more than one level of dependencies."
      switch "--installed",
             description: "Only list formulae that are currently installed."
      switch "--include-build",
             description: "Include all formulae that specify <formula> as `:build` type dependency."
      switch "--include-test",
             description: "Include all formulae that specify <formula> as `:test` type dependency."
      switch "--include-optional",
             description: "Include all formulae that specify <formula> as `:optional` type dependency."
      switch "--skip-recommended",
             description: "Skip all formulae that specify <formula> as `:recommended` type dependency."
      switch "--devel",
             description: "Show usage of <formula> by development builds."
      switch "--HEAD",
             description: "Show usage of <formula> by HEAD builds."
      switch "--tree",
             description: "Show dependents as a tree."
      switch :debug
      conflicts "--devel", "--HEAD"
      min_named :formula
    end
  end

  def uses
    uses_args.parse

    odeprecated "brew uses --devel" if args.devel?
    odeprecated "brew uses --HEAD" if args.HEAD?

    Formulary.enable_factory_cache!

    used_formulae_missing = false
    used_formulae = begin
      args.formulae
    rescue FormulaUnavailableError => e
      opoo e
      used_formulae_missing = true
      # If the formula doesn't exist: fake the needed formula object name.
      args.named.map { |name| OpenStruct.new name: name, full_name: name }
    end

    @use_runtime_dependents = args.installed? &&
                              !used_formulae_missing &&
                              !args.tree? &&
                              !args.include_build? &&
                              !args.include_test? &&
                              !args.include_optional? &&
                              !args.skip_recommended?

    if args.tree?
      used_formulae = used_formulae.sort_by(&:name)
      puts_dependents_tree used_formulae, args.recursive?
      return
    end

    uses = intersection_of_dependents used_formulae, args.recursive?

    return if uses.empty?

    puts Formatter.columns(uses.map(&:full_name).sort)
    odie "Missing formulae should not have dependents!" if used_formulae_missing
  end

  def intersection_of_dependents(used_formulae, recursive = false)
    if @use_runtime_dependents
      return used_formulae.map(&:runtime_installed_formula_dependents)
                          .reduce(&:&)
                          .select(&:any_version_installed?)
    end

    @formulae ||= (args.installed? ? Formula.installed : Formula).sort
    includes, ignores = argv_includes_ignores(ARGV)

    @formulae.select do |f|
      deps = if recursive
        recursive_includes(Dependency, f, includes, ignores)
      else
        reject_ignores(f.deps, ignores, includes)
      end

      used_formulae.all? do |ff|
        deps.any? do |dep|
          match = begin
            dep.to_formula.full_name == ff.full_name if dep.name.include?("/")
          rescue
            nil
          end
          next match unless match.nil?

          dep.name == ff.name
        end
      rescue FormulaUnavailableError
        # Silently ignore this case as we don't care about things used in
        # taps that aren't currently tapped.
        next
      end
    end
  end

  def puts_dependents_tree(used_formulae, recursive = false)
    used_formulae.each do |f|
      puts f.full_name
    end
    @dependents_stack = []
    recursive_dependents_tree(used_formulae, "", recursive)
  end

  def recursive_dependents_tree(formulae, prefix, recursive)
    includes, ignores = argv_includes_ignores(ARGV)
    dependents = intersection_of_dependents(formulae, false)

    max = dependents.length - 1
    @dependents_stack.push formulae.map(&:name)
    dependents.each_with_index do |dependent, i|
      tree_lines = if i == max
        "└──"
      else
        "├──"
      end

      display_s = "#{tree_lines} #{dependent.full_name}"
      is_circular = @dependents_stack.any? { |n| n.include?(dependent.name) }
      display_s = "#{display_s} (CIRCULAR DEPENDENT)" if is_circular
      puts "#{prefix}#{display_s}"

      next if !recursive || is_circular

      prefix_addition = if i == max
        "    "
      else
        "│   "
      end

      recursive_dependents_tree([dependent], prefix + prefix_addition, true)
    end

    @dependents_stack.pop
  end
end
