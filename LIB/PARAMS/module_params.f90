!> \brief params data structure, define all constant parameters for global use
!
!> \todo module actually only works for specific RHS, split between RHS parameters and program
!! parameters in future versions
! ********************************************************************************************

module module_params
    use mpi
    use module_ini_files_parser_mpi
    use module_bridge                       ! MPI general bridge module
    use module_helpers
    use module_t_files

    implicit none


    ! global user defined data structure for time independent variables
    type type_params

        ! maximal time for main time loop
        real(kind=rk) :: time_max=0.0_rk, walltime_max=1760.0_rk
        ! CFL criteria for time step calculation
        real(kind=rk) :: CFL=0.0_rk, krylov_err_threshold=1.0e-3_rk
        character(len=cshort) :: time_step_method="RungeKuttaGeneric"
        character(len=cshort) :: krylov_subspace_dimension="fixed"
        logical :: RKC_custom_scheme=.false.
        real(kind=rk), dimension(1:60) :: RKC_mu=0.0_rk, RKC_mu_tilde=0.0_rk, RKC_nu=0.0_rk, RKC_gamma_tilde=0.0_rk, RKC_c=0.0_rk
        ! dt
        real(kind=rk) :: dt_fixed=0.0_rk, dt_max=0.0_rk
        ! number of allowed time steps
        integer(kind=ik) :: nt=99999999, inicond_refinements=0
        ! number of stages "s" for the RungeKuttaChebychev method. Memory is always 6 registers
        ! independent of stages.
        integer(kind=ik) :: M_krylov = 12, N_dt_per_grid = 1, s = 4
        ! data writing frequency
        integer(kind=ik) :: write_freq=0
        ! data writing frequency
        character(len=cshort) :: write_method="fixed_time"
        ! data writing frequency
        real(kind=rk) :: write_time=0.1_rk, walltime_write = 999999.9_rk, walltime_last_write=0.0_rk, write_time_first=0.0_rk
        ! data next write time, store here the next time for output data
        real(kind=rk) :: next_write_time=0.0_rk
        ! this number is used when generating random grids.
        ! the default of 75% is useful for ghost node unit tests, but we sometimes
        ! have to create random grids that have no more than 1/8 active blocks so that
        ! we can still refine them by one level.
        real(kind=rk) :: max_grid_density = 0.75_rk

        ! butcher tableau containing coefficients for Runge-Kutta method
        real(kind=rk), dimension(:,:), allocatable :: butcher_tableau

        logical :: penalization=.false., mask_time_dependent_part=.false., mask_time_independent_part=.false., dont_use_pruned_tree_mask=.false.

        character(len=1), dimension(:), ALLOCATABLE :: symmetry_vector_component

        ! threshold for wavelet indicator
        real(kind=rk) :: eps=0.0_rk
        logical :: eps_normalized = .false.
        character(len=cshort) :: eps_norm="Linfty"
        logical :: force_maxlevel_dealiasing = .false.
        logical :: threshold_mask = .false.
        character(len=cshort) :: wavelet="not-initialized", wavelet_transform_type="harten-multiresolution"
        ! minimal level for blocks in data tree
        integer(kind=ik) :: min_treelevel=0
        ! maximal level for blocks in data tree
        integer(kind=ik) :: max_treelevel=0
        ! maximal numbers of trees in the forest
        integer(kind=ik) :: forest_size=1
        ! order of refinement predictor
        character(len=cshort) :: order_predictor="not-initialized", inicond_grid_from_file="no"
        ! order of spatial discretization
        character(len=cshort) :: order_discretization="not-initialized"
        character(len=cshort) :: coarsening_indicator="threshold-state-vector"
        character(len=cshort) :: coarsening_indicator_inicond="threshold-state-vector"
        logical, allocatable :: threshold_state_vector_component(:)
        ! decide if WABBIT should start from input files
        logical :: read_from_files
        ! files we want to read for inital cond.
        character(len=cshort), dimension(:), allocatable :: input_files

        integer(kind=ik), dimension(3) :: Bs=(/ 0, 0, 0 /)! number of block nodes
        integer(kind=ik) :: n_ghosts=0 ! number of ghost nodes

        ! In our grid definition with redundant points, at the coarse-fine interface values of one of the
        ! blocks need to be overwritten with the values from the other one. There are two choices:
        ! (1) overwrite coarser block with (decimated) fine block values (the solution until April 2020)
        ! (2) overwrite fine block with (interpolated) coarser block values (the new solution)
        ! In both cases, a redundant point exists. The solution (2) appears to be better with CDF44 wavelets, but
        ! in a purely hyperbolic test case without adaptation (static, non-equidistant grid), (2) diverges
        ! and (1) appears to be more stable.
        logical :: ghost_nodes_redundant_point_coarseWins = .false.
        logical :: iter_ghosts = .false.

        ! switch for mesh adaption
        logical :: adapt_mesh=.false., adapt_inicond=.false.
        logical :: out_of_memory = .false.
        ! number of allocated heavy data fields per process
        integer(kind=ik) :: number_blocks = -1_ik
        ! number of allocated data fields in heavy data array, number of fields
        ! in heavy work data (depend from time step scheme, ...)
        integer(kind=ik) :: n_eqn = 0_ik
        integer(kind=ik) :: N_mask_components = 0_ik

        ! block distribution for load balancing (also used for start distribution)
        character(len=cshort) :: block_distribution="sfc_hilbert"

        ! -------------------------------------------------------------------------------------
        ! physics
        ! -------------------------------------------------------------------------------------
        character(len=cshort) :: physics_type="not-initialized"
        real(kind=rk) :: domain_size(3)=0.0_rk
        integer(kind=ik) :: dim=2 ! can be 2 or 3

        ! -------------------------------------------------------------------------------------
        ! statistics
        ! -------------------------------------------------------------------------------------
        real(kind=rk) :: tsave_stats=99999999.9_rk, next_stats_time=0.0_rk
        integer(kind=ik) :: nsave_stats=99999999_ik

        ! -------------------------------------------------------------------------------------
        ! MPI
        ! -------------------------------------------------------------------------------------
        integer(kind=ik) :: rank=-1
        integer(kind=ik) :: number_procs=-1

        ! -------------------------------------------------------------------------------------
        ! bridge
        ! -------------------------------------------------------------------------------------
        ! bridge for connecting WABBIT to outdoor MPI_WORLD
        type(bridgeMPI) :: bridge
        logical :: bridge_exists = .false.

        !--------------------------------------------------------------------------------------
        !! particle connection
        !--------------------------------------------------------------------------------------
        !! - command to use for the particle program (over bridge)
        character(len=100) :: particleCommand=""
        !! - Usage of a common myWorld_comm
        logical :: bridgeCommonMPI
        !! - Consideration of the fluid side as master in case of several myWorld_comms
        logical :: bridgeFluidMaster

        ! -------------------------------------------------------------------------------------
        ! saving
        ! -------------------------------------------------------------------------------------
        integer(kind=ik) :: N_fields_saved=0
        character(len=cshort), allocatable, dimension(:) :: field_names
        logical :: use_iteration_as_fileid = .false.

        ! -------------------------------------------------------------------------------------
        ! unit test
        ! -------------------------------------------------------------------------------------
        logical :: test_treecode=.false., test_ghost_nodes_synch=.false., check_redundant_nodes=.false.

        ! -------------------------------------------------------------------------------------
        ! filter
        ! -------------------------------------------------------------------------------------
        ! type
        character(len=cshort) :: filter_type="no_filter"
        ! frequency
        integer(kind=ik) :: filter_freq=-1
        ! save filter strength sigma
        logical :: save_filter_strength
        logical :: filter_only_maxlevel = .false., filter_all_except_maxlevel = .false.

        ! -------------------------------------------------------------------------------------
        ! Boundary conditions
        ! -------------------------------------------------------------------------------------
        logical,dimension(3) :: periodic_BC = .true., symmetry_BC = .false.

    end type type_params

contains

    ! this file reads the ini file and distributes all the parameters to the
    ! various structs holding them
#include "ini_file_to_params.f90"

end module module_params
