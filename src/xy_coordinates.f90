module xy_coordinates
   !! Defining real space 2D coordinates for honeycomb lattice sites

   use hex_coordinates
   use hex_layout

   implicit none
   private

   public :: xy, xy_tile, xy_lattice, xy_print, xy_site, xy_ordered_union
   public :: hex2center, hex2corner, hex2site, corner2lattice

   integer, parameter :: N = 6 ! Number of vertices in a hexagon
   real(8), parameter :: PI = 4d0*atan(1d0) ! π to selected kind

   type xy
      !! Base type for 2D points
      real(8) :: x
      real(8) :: y
   contains
      generic :: operator(==) => eq_xy
      generic :: operator(/=) => neq_xy
      procedure, private :: eq_xy
      procedure, private :: neq_xy
   end type

   type, extends(xy) :: xy_site
      !! A 2D point extension for inequivalent sites
      !!     x,y   :: real-space coordinates
      !!     label :: A or B (sublattice)
      !!     key   :: for lattice lookup
      character(1) :: label
      integer      :: key=0
   end type

   type xy_tile
      !! Wrapper type for representing hexagons
      !! by storing all its vertices (1:6)
      type(xy_site),dimension(N) :: vertex
   end type

   type xy_lattice
      !! Wrapper type for storing dynamically
      !! sized collections of lattice sites
      type(xy_site),allocatable  :: site(:)
   contains
      procedure :: push_back
   end type

   interface xy_print
      procedure :: xy_class_print
      procedure :: xy_lattice_print
   end interface

contains

   ! PUBLIC API [private at bottom]

   pure elemental function hex2site(layout,H,label) result(site)
      !! Convert hex coordinates to real 2D lattice sites
      !! [returning the xy coordinates for the unique unit-cell,
      !!  sites "A" and "B": this of course does not account for
      !!  border effects, so would be suitable only for simple,
      !!  periodized, systems, which for now are out of scope.]
      !! Actual real-space layout has to be specified by passing
      !! a (scalar) unit_cell object.
      type(unit_cell),intent(in) :: layout
      type(hex),intent(in)       :: H
      character(1),intent(in)    :: label  !! A or B
      type(xy)                   :: center
      type(xy)                   :: offset
      type(xy_site)              :: site
      center = hex2center(layout,H)
      select case(label)
       case("A")
         offset = ith_corner_offset(layout,i=1)
       case("B")
         offset = ith_corner_offset(layout,i=2)
       case default
         error stop "Honeycomb sites must have 'A' or 'B' label"
      end select
      site%x = center%x + offset%x
      site%y = center%y + offset%y
      ! Lattice lookup
      site%key = H%key
   end function

   pure elemental function hex2corner(layout,H) result(corner)
      !! Convert hex coordinates to real 2D space
      !! [returning the xy coordinates for the hexagon corners,
      !!  as appropriatiely wrapped in a "xy_tile" derived type]
      !! Actual real-space layout has to be specified by passing
      !! a (scalar) unit_cell object.
      type(unit_cell),intent(in) :: layout
      type(hex),intent(in)       :: H
      type(xy)                   :: center
      type(xy)                   :: offset
      type(xy_tile)              :: corner
      integer                    :: i
      center = hex2center(layout,H)
      do i = 1,N
         offset = ith_corner_offset(layout,i)
         corner%vertex(i)%x = center%x + offset%x
         corner%vertex(i)%y = center%y + offset%y
         if(modulo(i,2)==1)then
            corner%vertex(i)%label = "A"
         else
            corner%vertex(i)%label = "B"
         endif
      enddo
   end function

   pure elemental function corner2lattice(corner) result(lattice)
      type(xy_tile),intent(in)   :: corner
      type(xy_lattice)           :: lattice
      lattice%site = corner%vertex
   end function

   pure elemental function hex2center(layout,H) result(center)
      !! Convert hex coordinates to real 2D space
      !! [returning the xy coordinates of the hexagon center]
      !! Actual real-space layout has to be specified by passing
      !! a (scalar) unit_cell object.
      type(unit_cell),intent(in) :: layout
      type(hex),intent(in)       :: H
      type(xy)                   :: center
      type(hex_orientation)      :: basis
      ! Project [q,r] along unit-cell basis to get [x,y]
      basis = layout%orientation
      center%x = basis%uq(1) * H%q + basis%ur(1) * H%r ! mixed math ok
      center%y = basis%uq(2) * H%q + basis%ur(2) * H%r ! mixed math ok
      ! Rescale and recenter according to unit-cell data
      center%x = center%x * layout%size + layout%origin(1)
      center%y = center%y * layout%size + layout%origin(2)
      ! Equivalent to:
      !        ⎡x⎤   ⎡uq(1)  ur(1)⎤   ⎡q⎤
      !        ⎥ ⎥ = ⎥            ⎥ × ⎥ ⎥ × size + origin
      !        ⎣y⎦   ⎣uq(2)  ur(2)⎦   ⎣r⎦
   end function

   pure function ith_corner_offset(layout,i) result(offset)
      !! Compute the i-th offset vector connecting the hexagon center
      !! to its corners, returning a (scalar) xy coordinate
      type(unit_cell),intent(in) :: layout
      integer,intent(in)         :: i
      type(xy)                   :: offset
      real(8)                    :: angle
      angle = 2d0*PI/N * (layout%orientation%angle + i) ! mixed math ok
      offset = xy(x=layout%size*cos(angle), y=layout%size*sin(angle))
   end function

   pure function xy_ordered_union(A,B) result(C)
      !! An ordered-keys set union for xy_lattices.
      !! It compares the lattice sites, looking at
      !! their x and y coordinates only: equal x,y
      !! entries are inserted in C just once, so to
      !! make it a set. A and B must be sets too.
      !! The sublattice labels are preserved in the
      !! process, assuming that two sites with the
      !! same x,y pertain to the same sublattice.
      !! For A the keys are assumed to be 1:size(A),
      !! and preserved as such (with an assertion).
      !! The keys of B are instead discarded, so to
      !! be replaced by size(A):size(C), which thus
      !! amounts to have result C uniquely indexed
      !! as 1, 2, ... , size(A) + size(B).
      !! This allows building consistently indexed
      !! matrices to act on the lattice array, such
      !! as real-space tight-binding hamiltonians.
      !! The keys would then be used to index other
      !! real space quantities, such as LDOS, Chern
      !! marker, local magnetization, and so on.
      type(xy_lattice),intent(in)   :: A
      type(xy_lattice),intent(in)   :: B
      type(xy_lattice)              :: C
      integer                       :: i,j
      C = A !copy all data of A into C
      do i = 1,size(B%site)
         if(all(B%site(i) /= A%site))then
            call C%push_back(B%site(i))
            C%site%key = size(A%site) + i
         endif
      enddo
      ! What if we allocate to (size(A)+size(B))
      ! memory to C, fill in the unique elements
      ! and then just truncate to the correct size
      ! by just calling pack(C,C/=0)? Assuming of
      ! course that C has been initialized to 0d0.
      ! Would it perform better than dynamically
      ! growing the array at each insertion? 0ˆ0-,
   end function

   ! THESE ARE PRIVATE NAMES

   pure elemental function eq_xy(A,B) result(isequal)
      !! polymorphic equality overload for xy class
      class(xy),intent(in) :: A,B
      logical              :: isequal
      isequal = abs(A%x - B%x) < 1d-12
      isequal = abs(A%y - B%y) < 1d-12 .and. isequal
   end function

   pure elemental function neq_xy(A,B) result(notequal)
      !! polymorphic inequality overload for xy class
      class(xy),intent(in) :: A,B
      logical              :: notequal
      notequal = .not.(eq_xy(A,B))
   end function

   pure subroutine push_back(vec,val)
      !! Poor man implementation of a dynamic
      !! array, a là std::vector (but without
      !! preallocation and smart doubling...)
      class(xy_lattice),intent(inout)  :: vec
      type(xy_site),intent(in)         :: val
      type(xy_site),allocatable        :: tmp(:)
      integer                          :: len
      if (allocated(vec%site)) then
         len = size(vec%site)
         allocate(tmp(len+1))
         tmp(:len) = vec%site
         call move_alloc(tmp,vec%site)
      else
         len = 1
         allocate(vec%site(len))
      end if
      !PUSH val at the BACK
      vec%site(len+1) = val
   end subroutine push_back

   impure elemental subroutine xy_class_print(S,unit,quiet)
      !! Pretty print of xy coordinates in static arrays
      class(xy),intent(in)         :: S
      integer,intent(in),optional  :: unit  !! default = $stdout
      logical,intent(in),optional  :: quiet !! default = .false.
      integer                      :: stdunit
      logical                      :: verbose
      if(present(quiet))then
         verbose = .not.quiet
      else
         verbose = .true.
      endif
      if(present(unit))then
         stdunit = unit
      else
         stdunit = 6 ! stdout
      endif
      if(verbose)then
         write(stdunit,*) "real-space coordinates [x,y]: ", S%x, S%y
      else
         write(stdunit,*) S%x, S%y
      endif
   end subroutine

   impure elemental subroutine xy_lattice_print(S,unit,quiet)
      !! Pretty print of xy coordinates in dynamic arrays
      type(xy_lattice),intent(in)  :: S
      integer,intent(in),optional  :: unit  !! default = $stdout
      logical,intent(in),optional  :: quiet !! default = .false.
      type(xy_site)                :: vector(size(S%site))
      integer                      :: stdunit
      logical                      :: verbose
      integer                      :: i
      if(present(quiet))then
         verbose = .not.quiet
      else
         verbose = .true.
      endif
      if(present(unit))then
         stdunit = unit
      else
         stdunit = 6 ! stdout
      endif
      vector = S%site
      do i = 1,size(vector)
         call xy_print(vector(i),unit=stdunit,quiet=.not.verbose)
      enddo
   end subroutine

end module xy_coordinates
