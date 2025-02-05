!> \brief wrapper for RHS call in time step function, computes RHS in work array
!! (inplace)
!!
!! calls RHS depending on physics
!!
!! butcher table, e.g.
!!
!! |   |    |    |   |
!! |---|----|----|---|
!! | 0 | 0  | 0  |  0|
!! |c2 | a21| 0  |  0|
!! |c3 | a31| a32|  0|
!! | 0 | b1 | b2 | b3|
!**********************************************************************************************

subroutine RHS_wrapper(time, params, hvy_block, hvy_rhs, hvy_mask, hvy_tmp, lgt_block, &
    lgt_active, lgt_n, lgt_sortednumlist, hvy_active, hvy_n, hvy_neighbor, tree_id)
   implicit none

    real(kind=rk), intent(in)           :: time
    type (type_params), intent(in)      :: params                       !> user defined parameter structure, hvy_active
    real(kind=rk), intent(inout)        :: hvy_rhs(:, :, :, :, :)       !> heavy work data array - block data
    real(kind=rk), intent(inout)        :: hvy_block(:, :, :, :, :)     !> heavy data array - block data
    real(kind=rk), intent(inout)        :: hvy_mask(:, :, :, :, :)      !> hvy_mask are qtys that depend on grid and not explicitly on time
    real(kind=rk), intent(inout)        :: hvy_tmp(:, :, :, :, :)
    integer(kind=ik), intent(inout)     :: lgt_block(:, :)              !> light data array
    integer(kind=ik), intent(inout)     :: hvy_active(:,:)              !> list of active blocks (heavy data)
    integer(kind=ik), intent(inout)     :: hvy_n(:)                     !> number of active blocks (heavy data)
    integer(kind=ik), intent(inout)     :: lgt_active(:,:)              !> list of active blocks (light data)
    integer(kind=ik), intent(inout)     :: lgt_n(:)                     !> number of active blocks (light data)
    integer(kind=tsize), intent(inout)  :: lgt_sortednumlist(:,:,:)     !> sorted list of numerical treecodes, used for block finding
    integer(kind=ik), intent(inout)     :: hvy_neighbor(:,:)            !> heavy data array - neighbor data
    integer(kind=ik), intent(in), optional :: tree_id
    
    real(kind=rk), dimension(3)         :: volume_int                   !> global integral
    real(kind=rk), dimension(3)         :: dx, x0                       !> spacing and origin of a block
    integer(kind=ik)                    :: k, dF, neqn, lgt_id, hvy_id  ! loop variables
    integer(kind=ik)                    :: g, rhs_tree_id              ! grid parameter, error variable
    integer(kind=ik), dimension(3)      :: Bs
    integer(kind=2)                     :: n_domain(1:3)
    real(kind=rk)                       :: t0, t1

    ! grid parameter
    Bs = params%Bs
    g  = params%n_ghosts
    t0 = MPI_wtime()
    n_domain = 0

    if (present(tree_id)) then
      rhs_tree_id = tree_id
    else
      rhs_tree_id = tree_ID_flow
    end if
    !-------------------------------------------------------------------------
    ! create mask function at current time
    !-------------------------------------------------------------------------
    t1 = MPI_wtime()
    call create_mask_tree(params, time, lgt_block, hvy_mask, hvy_tmp, &
        hvy_neighbor, hvy_active, hvy_n, lgt_active, lgt_n, lgt_sortednumlist)
    call toc( "RHS_wrapper::create_mask_tree", MPI_wtime()-t1 )


    !-------------------------------------------------------------------------
    ! 1st stage: init_stage. (called once, not for all blocks)
    !-------------------------------------------------------------------------
    t1 = MPI_wtime()
    ! performs initializations in the RHS module, such as resetting integrals
    hvy_id = hvy_active(1, rhs_tree_id) ! for this stage, just pass any block (result does not depend on block)
    call RHS_meta( params%physics_type, time, hvy_block(:,:,:,:,hvy_id), g, x0, dx, &
         hvy_rhs(:,:,:,:,hvy_id), hvy_mask(:,:,:,:,hvy_id), "init_stage" )

    !-------------------------------------------------------------------------
    ! 2nd stage: integral_stage. (called for all blocks)
    !-------------------------------------------------------------------------
    ! For some RHS, the eqn depend not only on local, block based qtys, such as
    ! the state vector, but also on the entire grid, for example to compute a
    ! global forcing term (e.g. in FSI the forces on bodies). As the physics
    ! modules cannot see the grid, (they only see blocks), in order to encapsulate
    ! them nicer, two RHS stages have to be defined: integral / local stage.
    do k = 1, hvy_n(rhs_tree_id)
        hvy_id = hvy_active(k, rhs_tree_id)
        ! convert given hvy_id to lgt_id for block spacing routine
        call hvy2lgt( lgt_id, hvy_id, params%rank, params%number_blocks )
        ! get block spacing for RHS
        call get_block_spacing_origin( params, lgt_id, lgt_block, x0, dx )

        if ( .not. All(params%periodic_BC) ) then
            ! check if block is adjacent to a boundary of the domain, if this is the case we use one sided stencils
            call get_adjacent_boundary_surface_normal( lgt_block(lgt_id, 1:lgt_block(lgt_id,params%max_treelevel+IDX_MESH_LVL)), &
            params%domain_size, params%Bs, params%dim, n_domain )
        endif

        call RHS_meta( params%physics_type, time, hvy_block(:,:,:,:, hvy_id), g, x0, dx,&
        hvy_rhs(:,:,:,:,hvy_id), hvy_mask(:,:,:,:,hvy_id), "integral_stage", n_domain )
    enddo


    !-------------------------------------------------------------------------
    ! 3rd stage: post integral stage. (called once, not for all blocks)
    !-------------------------------------------------------------------------
    ! in rhs module, used ror example for MPI_REDUCES
    hvy_id = hvy_active(1, rhs_tree_id) ! for this stage, just pass any block (result does not depend on block)
    call RHS_meta( params%physics_type, time, hvy_block(:,:,:,:, hvy_id), g, x0, dx, &
    hvy_rhs(:,:,:,:,hvy_id), hvy_mask(:,:,:,:,hvy_id), "post_stage" )
    call toc( "RHS_wrapper::integral-stage", MPI_wtime()-t1 )


    !-------------------------------------------------------------------------
    ! 4th stage: local evaluation of RHS on all blocks (called for all blocks)
    !-------------------------------------------------------------------------
    ! the second stage then is what you would usually do: evaluate local differential
    ! operators etc.

    t1 = MPI_wtime()
    do k = 1, hvy_n(rhs_tree_id)
        hvy_id = hvy_active(k, rhs_tree_id)
        ! convert given hvy_id to lgt_id for block spacing routine
        call hvy2lgt( lgt_id, hvy_id, params%rank, params%number_blocks )
        ! get block spacing for RHS
        call get_block_spacing_origin( params, lgt_id, lgt_block, x0, dx )

        if ( .not. All(params%periodic_BC) ) then
            ! check if block is adjacent to a boundary of the domain, if this is the case we use one sided stencils
            call get_adjacent_boundary_surface_normal( lgt_block(lgt_id, 1:lgt_block(lgt_id,params%max_treelevel+IDX_MESH_LVL)), &
            params%domain_size, params%Bs, params%dim, n_domain )
        endif

        call RHS_meta( params%physics_type, time, hvy_block(:,:,:,:, hvy_id), g, &
        x0, dx, hvy_rhs(:,:,:,:, hvy_id), hvy_mask(:,:,:,:, hvy_id), "local_stage", n_domain)
    enddo
    call toc( "RHS_wrapper::local-stage", MPI_wtime()-t1 )

    call toc( "RHS_wrapper_ALL", MPI_wtime()-t0 )
end subroutine RHS_wrapper
