"""
    mutable struct Simulation{S, A, VS}

A structure representing a Monte Carlo simulation.

# Fields
- `chains::Vector{S}`: Vector of independent systems.
- `algorithms::A`: List of algorithms.
- `steps::Int`: Number of MC sweeps.
- `t::Int`: Current time step.
- `schedulers::VS`: List of schedulers (one for each algorithm).
- `counters::Vector{Int}`: Counters for the schedulers (one for each algorithm).
- `path::String`: Simulation path.
- `verbose::Bool`: Flag for verbose output.
"""
mutable struct Simulation{S, A, VS}
    chains::Vector{S}
    algorithms::A
    steps::Int
    t::Int
    schedulers::VS
    counters::Vector{Int}
    path::String
    verbose::Bool

    """
    Create a new `Simulation` instance.

    # Arguments
    - `chains::Vector{S}`: Vector of independent systems.
    - `algorithms::A`: List of algorithms.
    - `schedulers::VS`: List of schedulers (one for each algorithm).
    - `steps::Int`: Number of MC sweeps.
    - `path::String="data"`: Simulation path.
    - `verbose::Bool=false`: Flag for verbose output.
    """
    function Simulation(
        chains::Vector{S},
        algorithms::A,
        schedulers::VS,
        steps::Int;
        path::String="data",
        verbose::Bool=false
    ) where {S,A,VS}
        @assert length(schedulers) == length(algorithms)
        @assert all(scheduler -> all(x -> 0 ≤ x ≤ steps, scheduler), schedulers)
        @assert all(scheduler -> issorted(scheduler), schedulers)
        t = 0
        counters = [findfirst(x -> x > 0, scheduler) for scheduler in schedulers]
        mkpath(path)
        return new{S, A, VS}(chains, algorithms, steps, t, schedulers, counters, path, verbose)
    end

end

"""
    Simulation(chains, algorithm_list, steps; path="data", verbose=false)

Create a new `Simulation` instance from a list of algorithm constructors.

# Arguments
- `chains`: Vector of independent systems.
- `algorithm_list`: List of algorithm constructors.
- `steps`: Number of MC sweeps.
- `path="data"`: Simulation path.
- `verbose=false`: Flag for verbose output.
"""
function Simulation(chains, algorithm_list, steps; path="data", verbose=false)
    schedulers_tmp = []
    algorithms_tmp = []
    algorithm_names = []
    for constructor in algorithm_list
        push!(algorithm_names, constructor.algorithm)
        scheduler = haskey(constructor, :scheduler) ? constructor.scheduler : 1:steps
        push!(schedulers_tmp, scheduler)
        kwargs = Base.structdiff(constructor, (algorithm=nothing, scheduler=nothing, dependencies=nothing))
        if haskey(constructor, :dependencies)
            parent_ids = findall(in(constructor.dependencies), algorithm_names)
            parent_instances = algorithms_tmp[parent_ids]
            kwargs = merge(kwargs, (dependencies=parent_instances,))
        end
        kwargs = merge(kwargs, (path=path, steps=steps, verbose=verbose))
        push!(algorithms_tmp, constructor.algorithm(chains; kwargs...))
    end
    schedulers = ntuple(k -> schedulers_tmp[k], length(schedulers_tmp))
    algorithms = ntuple(k -> algorithms_tmp[k], length(algorithms_tmp))
    return Simulation(chains, algorithms, schedulers, steps; path=path, verbose=verbose)
end

"""
    abstract type Algorithm

Abstract type for Monte Carlo algorithms.
"""
abstract type Algorithm end

"""
    initialise(::Algorithm, ::Simulation)

Initialise the algorithm for the given simulation.
"""
initialise(::Algorithm, ::Simulation) = nothing

"""
    make_step!(::Simulation, ::Algorithm)

Perform a single step of the algorithm in the simulation.
"""
make_step!(::Simulation, ::Algorithm) = nothing

"""
    finalise(::Algorithm, ::Simulation)

Finalise the algorithm for the given simulation.
"""
finalise(::Algorithm, ::Simulation) = nothing

"""
    run!(simulation::Simulation)

Run the Monte Carlo simulation.

# Arguments
- `simulation::Simulation`: The simulation instance to run.
"""
function run!(simulation::Simulation)
    try
        simulation.verbose && println("\n" * "-" ^ 50)
        simulation.verbose && println("\033[1;32mINITIALISATION\033[0m")
        for algorithm in simulation.algorithms
            initialise(algorithm, simulation)
        end
        write_summary(simulation)
        simulation.verbose && println("\033[1;32m\nRUNNING SIMULATION...\033[0m")
        sim_time = @elapsed for simulation.t in 1:simulation.steps
            for k in eachindex(simulation.algorithms)
                if simulation.t == simulation.schedulers[k][simulation.counters[k]]
                    make_step!(simulation, simulation.algorithms[k])
                    simulation.counters[k] += 1
                end
            end
        end
        simulation.verbose && println("\nSimulation completed in $sim_time s")
        update_summary(simulation, sim_time)
    finally
        simulation.verbose && println("\033[1;32m\nFINALISATION\033[0m")
        for algorithm in simulation.algorithms
            finalise(algorithm, simulation)
        end
        finalise_summary(simulation)
        simulation.verbose && println("\033[1;32m\nDONE\033[0m")
        simulation.verbose && println("-" ^ 50 * "\n")
    end
    return nothing
end

nothing
