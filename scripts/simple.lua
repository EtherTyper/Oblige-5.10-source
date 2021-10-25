----------------------------------------------------------------
--  SIMPLE ROOMS : CAVES and MAZES
----------------------------------------------------------------
--
--  Oblige Level Maker
--
--  Copyright (C) 2009-2013 Andrew Apted
--
--  This program is free software; you can redistribute it and/or
--  modify it under the terms of the GNU General Public License
--  as published by the Free Software Foundation; either version 2
--  of the License, or (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
----------------------------------------------------------------

--[[ *** CLASS INFORMATION ***

class CAVE_INFO
{
  W, H  -- size of cave (# of cells)

  x1, y1, x2, y2  -- bounding coords

  liquid_mode : keyword  -- "none", "some", "lake"

  step_mode   : keyword  -- "walkway", "up", "down", "mixed"

  sky_mode    : keyword  -- "none"
                         -- "some", "walkway"  (indoor rooms only)
                         -- "low_wall", "high_wall"  (outdoor rooms)

  cave : CAVE  -- raw generated cave

  blocks : array(AREA)  -- info for each 64x64 block

  floors : list(AREA)
  lakes  : list(AREA)

  wall   : AREA
  fence  : AREA
}


class AREA
{
  --| this info is used to describe each cave cell
  --| (and generally shared between multiple cells).

  wall   : boolean  -- true for solid walls
  liquid : boolean  -- true for a liquid floor
  sky    : boolean  -- true for a sky ceiling

  cx1, cy1, cx2, cy2   -- cell bounding box

  floor_h  -- floor height
   ceil_h  -- ceiling height

  floor_mat  -- floor material
   ceil_mat  -- ceiling material

  goal_type : keyword  -- set if area contains a goal (normally nil)
                       -- can be "portal" or "important".

  touching : list(AREA)   -- only used for visitable floors

  host_spots : list(BBOX)  -- spots which can host a torch/prefab

  decorations : list(BBOX)

  -- stuff for walkways only
  children : list[AREA]
}

--------------------------------------------------------------]]


SPOT_CLEAR = 0
SPOT_WALL  = 1
SPOT_LEDGE = 2


function Simple_generate_cave(R)
  local info = R.cave_info

  local map
  local cave

  local importants = {}
  local point_list = {}

  local is_lake = (info.liquid_mode == "lake")

  local need_border = is_lake or (info.sky_mode == "low_wall")


  local function cave_box_for_seed(sx, sy)
    local box =
    {
      cx1 = (sx - R.sx1) * 4 + 1
      cy1 = (sy - R.sy1) * 4 + 1
    }

    box.cx2 = box.cx1 + 3
    box.cy2 = box.cy1 + 3
    
    return box
  end


  local function set_side(cx1, cy1, cx2, cy2, side, value)
    local x1,y1, x2,y2 = geom.side_coords(side, cx1,cy1, cx2,cy2)

    map:fill(x1, y1, x2, y2, value)
  end


  local function set_corner(cx1, cy1, cx2, cy2, side, value)
    local cx, cy = geom.pick_corner(side, cx1, cy1, cx2, cy2)

    map:set(cx, cy, value)
  end


  local function create_map()
    info.W = R.sw * 4
    info.H = R.sh * 4

    info.blocks = table.array_2D(info.W, info.H)

    info.x1 = SEEDS[R.sx1][R.sy1].x1
    info.y1 = SEEDS[R.sx1][R.sy1].y1

    info.x2 = SEEDS[R.sx2][R.sy2].x2
    info.y2 = SEEDS[R.sx2][R.sy2].y2

    info.floors = {}

    local WALL_AREA =
    {
      wall = true
    }

    info.wall = WALL_AREA

    map = CAVE_CLASS.new(info.W, info.H)
  end


  local function mark_boundaries()
    -- this also sets most parts of the cave to zero

    for sx = R.sx1, R.sx2 do
    for sy = R.sy1, R.sy2 do
      local S = SEEDS[sx][sy]

      if S.room != R then continue end

      local cx = (sx - R.sx1) * 4 + 1
      local cy = (sy - R.sy1) * 4 + 1

      map:fill(cx, cy, cx+3, cy+3, 0)

      for dir = 2,8,2 do
        if not S:same_room(dir) then
          set_side(cx, cy, cx+3, cy+3, dir, sel(is_lake, -1, 1))
        end

        -- in lake mode, clear whole seeds that touch edge of map
        -- (i.e. which will have a sky border next to them)
        if is_lake and S:need_lake_fence(dir) then
          map:fill(cx, cy, cx+3, cy+3, -1)
        end
      end

      for dir = 1,9,2 do if dir != 5 then
        if not S:same_room(dir) then
          set_corner(cx, cy, cx+3, cy+3, dir, sel(is_lake, -1, 1))
        end
      end end

    end -- sx, sy
    end
  end


--[[
  local function clear_walks()
    for sx = R.sx1, R.sx2 do for sy = R.sy1, R.sy2 do
      local S = SEEDS[sx][sy]

      if S.room != R then continue end

      if S.is_walk and rand.odds(25) then

        local cx = (sx - R.sx1) * 4 + 1
        local cy = (sy - R.sy1) * 4 + 1

        for cx = cx, cx+3 do
          for cy = cy, cy+3 do
            if map:get(cx, cy) == 0 and rand.odds(25) then
              map:set(cx, cy, -1)
            end
          end
        end

      end
    end end -- sx, sy
  end
--]]


  local function clear_some_seeds()
    for sx = R.sx1, R.sx2 do
    for sy = R.sy1, R.sy2 do
      local S = SEEDS[sx][sy]

      if S.room != R then continue end

      if S.wall_dist < 1.1 then continue end

      if rand.odds(85) then continue end

      local cx = 1 + (sx - R.sx1) * 4
      local cy = 1 + (sy - R.sy1) * 4

      map:fill(cx, cy, cx+3, cy+3, -1)
    end
    end
  end


  local function point_for_portal(P)
    -- determine cave cell range:
    -- 1. if side of portal touches side of room, omit those cells
    -- 2. clear cells which touch portal, and two more away from it

    local b1 = cave_box_for_seed(P.sx1, P.sy1)
    local b2 = cave_box_for_seed(P.sx2, P.sy2)

    local cx1, cy1, cx2, cy2
    
    if geom.is_vert(P.side) then
      cx1 = b1.cx1
      cx2 = b2.cx2

      local yy = sel(P.side == 2, P.sy1, P.sy2)

      local S1 = SEEDS[P.sx1][yy]
      local S2 = SEEDS[P.sx2][yy]

      local N1 = S1:neighbor(4)
      local N2 = S2:neighbor(6)

      if not (N1 and N1.room == R) then cx1 = cx1 + 1 end
      if not (N2 and N2.room == R) then cx2 = cx2 - 1 end

      if P.side == 2 then
        cy1 = b1.cy1
        cy2 = b1.cy1 + 2
      else
        cy1 = b1.cy2 - 2
        cy2 = b1.cy2
      end

    else -- is_horiz(P.side)
      cy1 = b1.cy1
      cy2 = b2.cy2

      local xx = sel(P.side == 4, P.sx1, P.sx2)

      local S1 = SEEDS[xx][P.sy1]
      local S2 = SEEDS[xx][P.sy2]

      local N1 = S1:neighbor(2)
      local N2 = S2:neighbor(8)

      if not (N1 and N1.room == R) then cy1 = cy1 + 1 end
      if not (N2 and N2.room == R) then cy2 = cy2 - 1 end

      if P.side == 4 then
        cx1 = b1.cx1
        cx2 = b1.cx1 + 2
      else
        cx1 = b1.cx2 - 2
        cx2 = b1.cx2
      end
    end


    local IMP =
    {
      cx1 = cx1
      cy1 = cy1
      cx2 = cx2
      cy2 = cy2

      portal = P
    }

    table.insert(importants, IMP)

    local POINT =
    {
      x = math.i_mid(cx1, cx2)
      y = math.i_mid(cy1, cy2)
    }

    table.insert(point_list, POINT)
  end


  local function point_for_goal(G)
    -- expand bbox slightly
    local x1, y1 = G.x1 - 12, G.y1 - 12
    local x2, y2 = G.x2 + 12, G.y2 + 12

    -- convert to cell coordinates
    x1 = x1 - info.x1 ; y1 = y1 - info.y1
    x2 = x2 - info.x1 ; y2 = y2 - info.y1

    local cx1 = 1 + int(x1 / 64)
    local cy1 = 1 + int(y1 / 64)

    local cx2 = 1 + int((x2 + 63) / 64)
    local cy2 = 1 + int((y2 + 63) / 64)

    cx1 = math.clamp(1, cx1, map.w)
    cy1 = math.clamp(1, cy1, map.h)

    cx2 = math.clamp(1, cx2, map.w)
    cy2 = math.clamp(1, cy2, map.h)

    assert(cx1 <= cx2)
    assert(cy1 <= cy2)

    local IMP =
    {
      cx1 = cx1
      cy1 = cy1
      cx2 = cx2
      cy2 = cy2

      goal = G
    }

    table.insert(importants, IMP)

    local POINT =
    {
      x = math.i_mid(cx1, cx2)
      y = math.i_mid(cy1, cy2)
    }

    table.insert(point_list, POINT)
  end


  local function collect_important_points()
    each D in R.conns do
      if R == D.L1 and D.portal1 then
        point_for_portal(D.portal1)
      end
      if R == D.L2 and D.portal2 then
        point_for_portal(D.portal2)
      end
    end

    each G in R.goals do
      point_for_goal(G)
    end

    assert(#point_list > 0)

    R.point_list = point_list
    R.cave_imps  = importants
  end


  local function clear_importants()
    each imp in importants do
      map:fill(imp.cx1, imp.cy1, imp.cx2, imp.cy2, -1)
    end
  end


  local function is_cave_good(cave)
    -- check that all important parts are connected

    if not cave:validate_conns(point_list) then
      gui.debugf("cave failed connection check\n")
      return false
    end

    local p1 = point_list[1]

    cave.empty_id = cave.flood[p1.x][p1.y]

    assert(cave.empty_id)
    assert(cave.empty_id < 0)

    if not cave:validate_size(cave.empty_id) then
      gui.debugf("cave failed size check\n")
      return false
    end

    return true
  end


  local function generate_cave()
    map:dump("Empty Cave:")

    local solid_prob = 38

    if is_lake then
      solid_prob = 58
    end

    local MAX_LOOP = 20

    for loop = 1,MAX_LOOP do
      gui.debugf("Trying to make a cave: loop %d\n", loop)

      cave = map:copy()

      if loop >= MAX_LOOP then
        gui.printf("Failed to generate a usable cave! (%s)\n", R:tostr())

        -- emergency fallback
        cave:gen_empty()

        cave:flood_fill()

        is_cave_good(cave)  -- set empty_id
        break
      end

      cave:generate(solid_prob)

    cave:dump("Generated Cave:")
---      if is_lake then
---        cave:negate()
---      end

      cave:remove_dots()

      cave:flood_fill()

      if is_cave_good(cave) then
        break
      end

      -- randomly clear some seeds in the room.
      -- After each iteration the number of cleared cells will keep
      -- increasing, making it more likely to generate a valid cave.
      clear_some_seeds()
    end

    info.cave = cave

    if not is_lake then
      cave:solidify_pockets()
    end

    cave:dump("Filled Cave:")

    cave:find_islands()
  end


  ---| Simple_generate_cave |---

  -- create the cave object and make the boundaries solid
  create_map()

  collect_important_points()

  mark_boundaries()

  clear_importants()

  generate_cave()
end



function Simple_area_host_parts(R, A)
  --|
  --| figure out if this area can host something inside it
  --| (e.g. a torch or a cage prefab).
  --|
  --| stores a list of cell ranges in 'host_spots' field.
  --|

  local info = R.cave_info

  A.host_spots = {}

  -- TODO
end



function Simple_create_areas(R)
  --|
  --| sub-divide the floor of the cave into areas of differing heights.
  --|

  local info = R.cave_info
  local cave = info.cave

  local is_lake = (info.liquid_mode == "lake")

  -- groups are areas (rectangles) belonging to portals or importants
  -- and must be kept distinct (at the same height).
  local group_list
  local group_map


  local function install_area(A, a_cave, mul)
    for cx = 1, info.W do
    for cy = 1, info.H do
      if ((a_cave:get(cx, cy) or 0) * mul) > 0 then
        info.blocks[cx][cy] = A
      end
    end
    end
  end


  local function copy_cave_without_fences()
    local new_cave = info.cave:copy()

    if info.fence then
      for cx = 1, info.W do
      for cy = 1, info.H do
        if info.blocks[cx][cy] == info.fence then
          new_cave:set(cx, cy, nil)
        end
      end
      end
    end

    return new_cave
  end


  local function make_walkway()

    -- only have one area (the indentation / liquidy bits are considered a
    -- minor variation of it).
    local AREA =
    {
      touching = {}

      children = {}
    }

    table.insert(info.floors, AREA)

    each imp in R.cave_imps do
      imp.area = AREA
    end

    install_area(AREA, cave, -1)


    if info.liquid_mode == "lake" then return end


    local WALK1 =
    {
      indent = 1
    }

    local walk_way = copy_cave_without_fences()

    -- remove importants from it
    each imp in R.cave_imps do
      walk_way:fill(imp.cx1, imp.cy1, imp.cx2, imp.cy2, 1)
    end

    walk_way:negate()
    walk_way:shrink8(true)
--    walk_way:shrink(true)
    walk_way:remove_dots()

    install_area(WALK1, walk_way, 1)


    local WALK2 =
    {
      indent = 2
      liquid = true
    }

    if info.sky_mode == "some" then
      WALK2.sky = true
    end

    walk_way:shrink8(true)
--    walk_way:shrink(true)
    walk_way:remove_dots()

    install_area(WALK2, walk_way, 1)


    table.insert(AREA.children, WALK1)
    table.insert(AREA.children, WALK2)
  end


  local function add_group_to_map(G)
    table.insert(group_list, G)

    for x = G.cx1, G.cx2 do
    for y = G.cy1, G.cy2 do
      group_map.cells[x][y] = G
    end
    end
  end


  local function remove_group_from_map(G)
    table.kill_elem(group_list, G)

    for x = G.cx1, G.cx2 do
    for y = G.cy1, G.cy2 do
      group_map.cells[x][y] = nil
    end
    end
  end


  local function create_group_map()
    group_list = {}

    group_map = CAVE_CLASS.blank_copy(info.cave)

    each G in R.cave_imps do
      add_group_to_map(G)
    end
  end


  local function grow_step_areas()

    local pos_list = { }

    pos_list[1] =
    {
      x = R.point_list[1].x
      y = R.point_list[1].y
    }


    local free  = copy_cave_without_fences()
    local f_cel = free.cells

    local step
    local s_cel
    local size

    local cw = free.w
    local ch = free.h

    -- current bbox : big speed up by limiting the scan area
    local cx1, cy1
    local cx2, cy2

    local touched_groups
    

    -- mark free areas with zero instead of negative
    for fx = 1, cw do
    for fy = 1, ch do
      if (f_cel[fx][fy] or 0) < 0 then
        f_cel[fx][fy] = 0
      end
    end
    end


    local function touch_a_group(G)
      remove_group_from_map(G)

      table.insert(touched_groups, G)

      -- add the whole group to the current step
      for x = G.cx1, G.cx2 do
      for y = G.cy1, G.cy2 do
        s_cel[x][y] = 1
        f_cel[x][y] = 1

        size = size + 1
      end
      end

      -- update bbox
      cx1 = math.min(cx1, G.cx1)
      cy1 = math.min(cy1, G.cy1)

      cx2 = math.max(cx2, G.cx2)
      cy2 = math.max(cy2, G.cy2)
    end


    local function grow_add(x, y)
      s_cel[x][y] = 1
      f_cel[x][y] = 1

      size = size + 1

      -- update bbox
      if x < cx1 then cx1 = x end
      if x > cx2 then cx2 = x end

      if y < cy1 then cy1 = y end
      if y > cy2 then cy2 = y end

      if group_map.cells[x][y] then
        touch_a_group(group_map.cells[x][y])
      end
    end


    local function grow_horiz(y, prob)
      for x = cx1, cx2 do
        if x > 1 and s_cel[x][y] == 1 and s_cel[x-1][y] == 0 and f_cel[x-1][y] == 0 and rand.odds(prob) then
          grow_add(x-1, y)
        end
      end

      for x = cx2, cx1, -1 do
        if x < cw and s_cel[x][y] == 1 and s_cel[x+1][y] == 0 and f_cel[x+1][y] == 0 and rand.odds(prob) then
          grow_add(x+1, y)
        end
      end
    end


    local function grow_vert(x, prob)
      for y = cy1, cy2 do
        if y > 1 and s_cel[x][y] == 1 and s_cel[x][y-1] == 0 and f_cel[x][y-1] == 0 and rand.odds(prob) then
          grow_add(x, y-1)
        end
      end

      for y = cy2, cy1, -1 do
        if y < ch and s_cel[x][y] == 1 and s_cel[x][y+1] == 0 and f_cel[x][y+1] == 0 and rand.odds(prob) then
          grow_add(x, y+1)
        end
      end
    end


    local function grow_it(prob)
      for y = cy1, cy2 do
        grow_horiz(y, prob)
      end

      for x = cx1, cx2 do
        grow_vert(x, prob)
      end
    end


    local function grow_an_area(cx, cy, prev_A)

-- free:dump("Free:")

      step  = CAVE_CLASS.blank_copy(free)
      s_cel = step.cells

      step:set_all(0)

      size = 0

      touched_groups = {}

      cx1 = cx ; cx2 = cx
      cy1 = cy ; cy2 = cy

      -- set initial point
      grow_add(cx, cy)

      local count = rand.pick { 3, 4, 5 }

      grow_it(100)

      for loop = 1, count do
        grow_it(50)
      end

      if size < 4 or #touched_groups > 0 then
        grow_it(100)
        grow_it(40)
      end

step:dump("Step:")

      -- when the step is too small, merge it into previous area
      if size < 4 and prev_A then

        install_area(prev_A, step, 1)

        prev_A.cx1 = math.min(prev_A.cx1, cx1)
        prev_A.cy1 = math.min(prev_A.cy1, cy1)
        prev_A.cx2 = math.max(prev_A.cx2, cx2)
        prev_A.cy2 = math.max(prev_A.cy2, cy2)

      else
        local AREA =
        {
          touching = {}

          cx1 = cx1, cy1 = cy1
          cx2 = cx2, cy2 = cy2
        }

        table.insert(info.floors, AREA)

        install_area(AREA, step, 1)

        prev_A = AREA
      end


      -- remember area of covered groups (e.g. for outgoing heights)
      each G in touched_groups do
        G.area = prev_A

        if G.portal then
          prev_A.goal_type = "portal"
        else
          prev_A.goal_type = "important"
        end
      end


      -- find new positions for growth

      for x = cx1, cx2 do
      for y = cy1, cy2 do
        if s_cel[x][y] != 1 then continue end

        for dir = 2,8,2 do
          local nx, ny = geom.nudge(x, y, dir)
          if free:valid_cell(nx, ny) and f_cel[nx][ny] == 0 then
            table.insert(pos_list, { x=nx, y=ny, prev=prev_A })
          end
        end
      end -- x, y
      end
    end


    --| grow_an_area |--

    while #pos_list > 0 do
      local pos = table.remove(pos_list, rand.irange(1, #pos_list))

      -- ignore out-of-date positions
      if f_cel[pos.x][pos.y] != 0 then continue end

      grow_an_area(pos.x, pos.y, pos.prev)
    end
  end


  local function determine_touching_areas()
    local W = info.W
    local H = info.H

    for x = 1, W do
    for y = 1, H do
      local A1 = info.blocks[x][y]

      if not (A1 and A1.touching) then continue end

      for dir = 2,4,2 do
        local nx, ny = geom.nudge(x, y, dir)

        if not cave:valid_cell(nx, ny) then continue end

        local A2 = info.blocks[nx][ny]

        if not (A2 and A2.touching) then continue end

        if A2 != A1 then
          table.add_unique(A1.touching, A2)
          table.add_unique(A2.touching, A1)
        end
      end
    end  -- x, y
    end

    -- verify all areas touch at least one other
    if #info.floors > 1 then
      each A in info.floors do
        assert(not table.empty(A.touching))
      end
    end
  end


  local function set_walls()
    for x = 1, info.W do
    for y = 1, info.H do
      local val = cave:get(x, y)

      if (val or 0) > 0 then
        info.blocks[x][y] = info.wall
      end
    end
    end
  end


  ---| Simple_create_areas |---

  if info.step_mode == "walkway" then
    make_walkway()
  else
    create_group_map()

    grow_step_areas()

    if #group_list > 0 then
      error("Cave steps failed to cover all important chunks\n")
    end
  end

  determine_touching_areas()

  if not is_lake then
    set_walls()
  end
end



function Simple_bunch_areas(R, mode)
  --|
  --| this picks a bunch of step areas which will become either liquid
  --| or sky (depending on 'mode' parameter).
  --| 
  
  local info = R.cave_info


  local function setup()
    each A in info.floors do
      if A.goal_type then A.near_bunch = 0 end
    end
  end


  local function pick_start_area()
    local poss = {}

    each A in info.floors do
      if not A.near_bunch then
        table.insert(poss, A)
      end
    end

    if table.empty(poss) then return nil end

    return rand.pick(poss)
  end


  local function touches_the_list(N, list, except)
    each N2 in N.touching do
      if list[N2] and N2 != except then
        return true
      end
    end

    return false
  end


  local function grow_bunch(list)
    local poss = {}

    each A,_ in list do
      each N in A.touching do
        if list[N] then continue end
        if N.near_bunch then continue end

        if touches_the_list(N, list, A) then continue end

        table.insert(poss, N)
      end
    end

    if table.empty(poss) then return false end

    local A2 = rand.pick(poss)

    list[A2] = 1

    return true
  end


  local function install_bunch(list)
    local head_A

    each A,_ in list do
      if not head_A then head_A = A end

      if mode == "sky"    then A.sky_bunch    = head_A ; A.sky    = true end
      if mode == "liquid" then A.liquid_bunch = head_A ; A.liquid = true end

      A.near_bunch = 0

      each N in A.touching do
        if not N.near_bunch or N.near_bunch > 1 then
          N.near_bunch = 1
        end
      end
    end

    -- extra health to compensate player for crossing the river
    if mode == "liquid" and LEVEL.liquid.damage then
      R.hazard_health = R.hazard_health + 30
    end
  end


  local function clear()
    each A in info.floors do
      A.near_bunch = nil
    end
  end


  ---| Simple_bunch_areas |---

  if info.step_mode == "walkway" then return end
  if info.liquid_mode == "lake"  then return end

  if mode == "sky"    and info.sky_mode    != "some" then return end
  if mode == "liquid" and info.liquid_mode != "some" then return end

  setup()

  local try_count = int(#info.floors / rand.sel(50, 8, 14))

  for i = 1, try_count do
    local A1 = pick_start_area()

    if not A1 then break; end  -- nothing is possible

    local list = { [A1] = 1 }

    while grow_bunch(list) and rand.odds(64) do
      -- keep growing...
    end

    if table.size(list) >= 2 then
      install_bunch(list)
    end
  end

  clear()
end



function Simple_heights_near_area(R, A)
  local info = R.cave_info
  local cave = info.cave

  local min_floor_h =  9e9
  local max_floor_h = -9e9

  local min_ceil_h =  9e9
  local max_ceil_h = -9e9

  for x = 1, info.W do
  for y = 1, info.H do
    for dir = 2,4 do
      local nx, ny = geom.nudge(x, y, dir)

      if not cave:valid_cell(nx, ny) then continue end

      local A1 = info.blocks[x][y]
      local A2 = info.blocks[nx][ny]

      if (A2 == A) then
        A1, A2 = A2, A1
      end

      if not A2 or (A1 != A) or (A2 == A) then continue end

      if A2.floor_h then
        min_floor_h = math.min(min_floor_h, A2.floor_h)
        max_floor_h = math.max(max_floor_h, A2.floor_h)
      end

      if A2.ceil_h then
        min_ceil_h = math.min(min_ceil_h, A2.ceil_h)
        max_ceil_h = math.max(max_ceil_h, A2.ceil_h)
      end
    end
  end -- x, y
  end

  if min_floor_h > max_floor_h then
    min_floor_h = nil
    max_floor_h = nil
  end

  if min_ceil_h > max_ceil_h then
    min_ceil_h = nil
    max_ceil_h = nil
  end

  return min_floor_h, max_floor_h,
         min_ceil_h,  max_ceil_h
end



function Simple_floor_heights(R, entry_h)
  local info = R.cave_info


  local z_change_prob = rand.sel(15, 40, 10)

  if info.step_mode == "up" or info.step_mode == "down" then
    z_change_prob = 0
  end


  local function floor_for_river(bunch_A, h)
    assert(not bunch_A.floor_h)

    local diff_h = 16

    -- determine minimum of all areas touching the river
    each A in info.floors do
      if A.liquid_bunch != bunch_A then continue end

      each N in A.touching do
        if N.liquid_bunch then continue end

        if N.floor_h then
          h = math.min(h, N.floor_h - diff_h)
        end
      end
    end

    each A in info.floors do
      if A.liquid_bunch == bunch_A then
        A.floor_h = h
      end
    end

    return h
  end


  local function spread_river_banks(bunch_A, h)
    --| ensure all areas touching the river get a floor height now
    --| (to prevent those areas becoming lower than the river).

    each A in info.floors do
      if A.liquid_bunch != bunch_A then continue end

      each N in A.touching do
        if N.liquid_bunch then continue end

        if not N.floor_h then
          N.floor_h = h + rand.pick({8, 16, 24})
        end
      end
    end
  end


  local function visit_area(A, z_dir, h)
    --|
    --| recursively spread floors heights into each area
    --|

    assert(not A.visited)
    A.visited = true

    if rand.odds(z_change_prob) then
      z_dir = - z_dir
    end


    -- floor --

    if A.floor_h then
      h = A.floor_h
    elseif A.liquid_bunch then
      h = floor_for_river(A.liquid_bunch, h)
    else
      A.floor_h = h
    end

    if A.liquid_bunch then
      spread_river_banks(A.liquid_bunch, h)
    end


    -- ceiling --

    if R.is_outdoor then
      -- no ceil_h (done later using sky_rects)
    elseif A.goal_type then
      A.ceil_h = h + 192
    else
      A.ceil_h = h + rand.pick { 128, 192,192,192, 288 }
    end


    rand.shuffle(A.touching)

    each N in A.touching do
      if not N.visited then
        local new_h = h + z_dir * rand.sel(35, 8, 16)
        visit_area(N, z_dir, new_h)
      end
    end
  end


  local function find_entry_area()
    each imp in R.cave_imps do
      assert(imp.area)
      if imp.portal and imp.portal.floor_h then
        return imp.area
      end
    end

    return rand.pick(info.floors)
  end


  local function transfer_heights()
    -- transfer heights to importants and portals
    each imp in R.cave_imps do
      assert(imp.area)
      assert(imp.area.floor_h)

      local G = imp.goal
      local P = imp.portal

      if G then
        G.z1 = imp.area.floor_h
        G.z2 = G.z1 + 160
      end

      if P and not P.floor_h then
        Portal_set_floor(P, imp.area.floor_h)
      end

      if P and P.door_kind and not P.added_door then
        Areas_add_wall(R, P.door_kind, P.sx1, P.sy1, P.sx2, P.sy2, P.side, P.floor_h, P.conn)
        P.added_door = true
      end
    end 
  end


  local function update_min_max_floor()
    each A in info.floors do
      R.min_floor_h = math.min(R.min_floor_h, A.floor_h)
      R.max_floor_h = math.max(R.max_floor_h, A.floor_h)
    end
  end


  local function update_walk_ways()
    each A in info.floors do
      if not A.children then continue end

      each WALK in A.children do
        WALK.floor_h = A.floor_h - WALK.indent * 12

        if A.ceil_h then
          WALK.ceil_h = A.ceil_h + WALK.indent * 64
        end
      end
    end
  end


  local function update_fences()
    if info.liquid_mode == "lake" then
      info.fence.floor_h = R.max_floor_h + 96
    end

    if info.sky_mode == "low_wall" then
      info.wall.floor_h = R.max_floor_h + 80
    end
  end


  local function update_lakes()
    for pass = 1,4 do
      each A in info.lakes do
        if not A.floor_h then
        
          local f_h = Simple_heights_near_area(R, A)

          if f_h then
            A.floor_h = f_h - rand.pick({ 8, 16, 24 })
          elseif pass == 4 then
            error("Lake failed to get a height")
          end

        end
      end
    end
  end


  local function ceiling_for_sky_bunch(bunch_A)
    local h = bunch_A.ceil_h or 0

    each A in info.floors do
      if A.sky_bunch != bunch_A then continue end

      each N in A.touching do
        if N.sky_bunch then continue end

        if N.ceil_h then
          h = math.max(h, N.ceil_h)
        end
      end
    end

    h = h + rand.pick({ 32,48,64,96 })

    each A in info.floors do
      if A.sky_bunch == bunch_A then
        A.ceil_h = h
      end
    end
  end


  local function update_sky_bunches()
    each A in info.floors do
      if A.sky_bunch == A then
        ceiling_for_sky_bunch(A)
      end
    end
  end


  ---| Simple_floor_heights |---

  local z_dir

  if info.step_mode == "up" then
    z_dir = 1
  elseif info.step_mode == "down" then
    z_dir = -1
  else
    z_dir = rand.sel(37, 1, -1)
  end

  local entry_area = find_entry_area()

  visit_area(entry_area, z_dir, entry_h)

  transfer_heights()

  update_min_max_floor()
  update_walk_ways()
  update_fences()
  update_lakes()
  update_sky_bunches()
end



function Simple_render_cave(R)

  local info = R.cave_info


  local cave = info.cave

  local cave_tex = R.wall_mat or "_ERROR"

  local is_lake = (info.liquid_mode == "lake")

  -- the delta map specifies how to move each corner of the 64x64 cells
  -- (where the cells form a continuous mesh).
  local delta_x_map
  local delta_y_map

  local dw = info.W + 1
  local dh = info.H + 1

  local B_CORNERS = { 1,3,9,7 }


  local function grab_cell(x, y)
    if not cave:valid_cell(x, y) then
      return nil
    end

    local A = info.blocks[x][y]

    -- in some places we build nothing (e.g. other rooms)
    if A == nil then return nil end

    -- check for a solid cell
    if A.wall then return EXTREME_H end

    -- otherwise there should be a floor area here

    assert(A)

    local f_h = assert(A.floor_h)

    -- take ceiling into account too
    local c_h = A.ceil_h

    if c_h then
      f_h = f_h + bit.band(c_h, 511) / 1024
    end

    return f_h
  end


  local function analyse_corner(x, y)
    --  A | B
    --  --+--
    --  C | D

    local A = grab_cell(x-1, y)
    local B = grab_cell(x,   y)
    local C = grab_cell(x-1, y-1)
    local D = grab_cell(x,   y-1)

    -- never move a corner at edge of room
    if not A or not B or not C or not D then
      return
    end

    -- pick highest floor (since that can block a lower floor)
    -- [solid cells will always override floor cells]

    local max_h = math.max(A, B, C, D) - 0.01

    A = (A > max_h)
    B = (B > max_h)
    C = (C > max_h)
    D = (D > max_h)

    -- no need to move when all cells are the same

    if A == B and A == C and A == D then
      return
    end

    local x_mul =  1
    local y_mul = -1

    -- flip horizontally and/or vertically to ease analysis
    if not A and B then
      A, B = B, A
      C, D = D, C
      x_mul = -1

    elseif not A and C then
      A, C = C, A
      B, D = D, B
      y_mul = 1

    elseif not A and D then
      A, D = D, A
      B, C = C, B
      x_mul = -1
      y_mul =  1
    end

    assert(A)

    --- ANALYSE! ---

    if not B and not C and not D then
      -- sticking out corner
      if rand.odds(90) then delta_x_map[x][y] = -16 * x_mul end
      if rand.odds(90) then delta_y_map[x][y] = -16 * y_mul end

    elseif B and not C and not D then
      -- horizontal wall
      if rand.odds(55) then delta_y_map[x][y] = -24 * y_mul end

    elseif C and not B and not D then
      -- vertical wall
      if rand.odds(55) then delta_x_map[x][y] = -24 * x_mul end

    elseif D and not B and not C then
      -- checkerboard
      -- (not moving it : this situation should not occur)

    else
      -- an empty corner
      -- expand a bit, but not enough to block player movement
          if not B then y_mul = -y_mul
      elseif not C then x_mul = -x_mul
      end

      if rand.odds(80) then delta_x_map[x][y] = 12 * x_mul end
      if rand.odds(80) then delta_y_map[x][y] = 12 * y_mul end
    end
  end


  local function create_delta_map()
    delta_x_map = table.array_2D(dw, dh)
    delta_y_map = table.array_2D(dw, dh)

    if square_cave then return end

    for x = 1, dw do
    for y = 1, dh do
      analyse_corner(x, y)
    end
    end
  end


  local function brush_for_cell(x, y)
    local bx = info.x1 + (x - 1) * 64
    local by = info.y1 + (y - 1) * 64

    local coords = {}

    each side in B_CORNERS do
      local dx, dy = geom.delta(side)

      local fx = bx + sel(dx < 0, 0, 64)
      local fy = by + sel(dy < 0, 0, 64)

      local cx =  x + sel(dx < 0, 0, 1)
      local cy =  y + sel(dy < 0, 0, 1)

      fx = fx + (delta_x_map[cx][cy] or 0)
      fy = fy + (delta_y_map[cx][cy] or 0)

      table.insert(coords, { x=fx, y=fy })
    end

    return coords
  end


  local function cell_middle(x, y)
    local mx = info.x1 + (x - 1) * 64 + 32
    local my = info.y1 + (y - 1) * 64 + 32
  
    return mx, my
  end


  local function choose_tex(last, tab)
    local tex = rand.key_by_probs(tab)

    if last then
      for loop = 1,5 do
        if not Mat_similar(last, tex) then break; end
        tex = rand.key_by_probs(tab)
      end
    end

    return tex
  end


  local function render_cell(x, y)
    local A = info.blocks[x][y]

    if not A then return end


    local f_h = A.floor_h
    local c_h = A.ceil_h  

    local f_mat = A.floor_mat or R.floor_mat or cave_tex
    local c_mat = A. ceil_mat or R.ceil_mat  or cave_tex

    if A.wall then f_mat = A.wall_mat or R.wall_mat or cave_tex end

    local f_liquid = A.liquid
    local c_sky    = A.sky


    local f_brush = brush_for_cell(x, y)

    if f_h then
      Brush_add_top(f_brush, f_h)
    end

    if f_liquid then
      Brush_mark_liquid(f_brush)
    else
      Brush_set_mat(f_brush, f_mat, f_mat)
    end

    brush_helper(f_brush)


    if c_h then
      local c_brush = brush_for_cell(x, y)

      Brush_add_bottom(c_brush, c_h)

      if c_sky then
        Brush_mark_sky(c_brush)
      else
        Brush_set_mat(c_brush, c_mat, c_mat)
      end

      brush_helper(c_brush)
    end
  end


  local function do_spot_floor(A, x, y)
    local A2 = info.blocks[x][y]

    if A != A2 then return end

    local poly = brush_for_cell(x, y)

    gui.spots_fill_poly(poly, SPOT_CLEAR)
  end


  local function do_spot_wall(A, x, y)
    local A2 = info.blocks[x][y]

    if A2 == A then return end

    local near_area = false

    for dir = 1,9 do if dir != 5 then
      local nx, ny = geom.nudge(x, y, dir)

      if not cave:valid_cell(nx, ny) then continue end

      if info.blocks[nx][ny] == A then
        near_area = true
        break;
      end
    end end -- dir

    if near_area then 
      local poly = brush_for_cell(x, y)

      if cell == nil then
        gui.spots_fill_poly(poly, SPOT_WALL)
      else
        gui.spots_fill_poly(poly, SPOT_LEDGE)
      end
    end
  end


  local function do_spot_decor(dec)
    local poly = Brush_new_quad(dec.x1, dec.y1, dec.x2, dec.y2)

    gui.spots_fill_poly(poly, SPOT_LEDGE)
  end


  local function determine_spots(A)
    -- determine bbox of area

    -- TODO: this is whole cave, ideally have just the area

    local x1 = info.x1 + 10
    local y1 = info.y1 + 10

    local x2 = info.x2 - 10
    local y2 = info.y2 - 10

    gui.spots_begin(x1, y1, x2, y2, SPOT_LEDGE)


    -- step 1 : handle floors

    for cx = 1, info.W do
    for cy = 1, info.H do
      do_spot_floor(A, cx, cy)
    end
    end

    -- step 2 : handle nearby walls

    for cx = 1, info.W do
    for cy = 1, info.H do
      do_spot_wall(A, cx, cy)
    end
    end

    -- step 3 : remove decorations

    if A.decorations then
      each dec in A.decorations do
        do_spot_decor(dec)
      end
    end


    -- now grab all the spots...

    local item_spots = {}

    gui.spots_get_items(item_spots)

    -- mark exclusion zones (e.g. area around a teleporter).
    -- gotta do it _after_ getting the item spots

    each zone in R.exclusion_zones do
      if zone.kind == "empty" then
        local poly = Brush_new_quad(zone.x1, zone.y1, zone.x2, zone.y2)
        gui.spots_fill_poly(poly, SPOT_LEDGE)
      end
    end

  --  gui.spots_dump("Spot grid")


    local mon_spots  = {}

    gui.spots_get_mons(mon_spots)

    if table.empty(item_spots) and mon_spots[1] then
      table.insert(item_spots, mon_spots[1])
    end


    -- add to room, set Z positions
    local f_h = assert(A.floor_h)
    local c_h = A.ceil_h or (f_h + 160)

    each spot in item_spots do
      spot.z1 = f_h
      spot.z2 = c_h

      table.insert(R.item_spots, spot)
    end

    each spot in mon_spots do
      spot.z1 = f_h
      spot.z2 = c_h

      spot.face_away = R:find_nonfacing_spot(spot.x1, spot.y1, spot.x2, spot.y2)

      table.insert(R.mon_spots, spot)
    end

    gui.spots_end()
  end


--[[ OLD
  local function heights_near_island(island)
    local min_floor =  9e9
    local max_ceil  = -9e9
  
    for x = 1, info.W do
    for y = 1, info.H do
      if ((island:get(x, y) or 0) > 0) then
        for dir = 2,8,2 do
          local nx, ny = geom.nudge(x, y, dir)

          if not island:valid_cell(nx, ny) then continue end

          local A = R.area_map:get(nx, ny)
          if not A then continue end

          min_floor = math.min(min_floor, A.floor_h)
          max_ceil  = math.max(max_ceil , A.ceil_h)
        end
      end
    end  -- x, y
    end

--!!!! FIXME  assert(min_floor < max_ceil)

    return min_floor, max_ceil
  end


  local function render_liquid_area(island)
    -- create a lava/nukage pit

    local f_mat = R.floor_mat or cave_tex
    local c_mat = R.ceil_mat  or cave_tex
    local l_mat = LEVEL.liquid.mat

    local f_h, c_h = heights_near_island(island)

    -- FIXME!! should not happen
    if f_h >= c_h then return end

    f_h = f_h - 24
    c_h = c_h + 64

    -- TODO: fireballs for Quake

    for x = 1, cave.w do
    for y = 1, cave.h do

      if ((island:get(x, y) or 0) > 0) then

        -- do not render a wall here
        cave:set(x, y, 0)

        local f_brush = brush_for_cell(x, y)
        local c_brush = brush_for_cell(x, y)

        if PARAM.deep_liquids then
          Brush_add_top(f_brush, f_h-128)
          Brush_set_mat(f_brush, f_mat, f_mat)

          brush_helper(f_brush)

          local l_brush = brush_for_cell(x, y)

          table.insert(l_brush, 1, { m="liquid", medium=LEVEL.liquid.medium })

          Brush_add_top(l_brush, f_h)
          Brush_set_mat(l_brush, "_LIQUID", "_LIQUID")

          brush_helper(l_brush)

          -- TODO: lighting

        else
          Brush_add_top(f_brush, f_h)

          -- damaging
          f_brush[#f_brush].special = LEVEL.liquid.special

          -- lighting
          if LEVEL.liquid.light then
            f_brush[#f_brush].light = LEVEL.liquid.light
          end

          Brush_set_mat(f_brush, l_mat, l_mat)

          brush_helper(f_brush)
        end

        -- common ceiling code

        Brush_add_bottom(c_brush, c_h)
        Brush_set_mat(c_brush, c_mat, c_mat)

        if c_mat == "_SKY" then
          table.insert(c_brush, 1, { m="sky" })
        end

        brush_helper(c_brush)
      end

    end end -- x, y
  end
--]]


  local function add_liquid_pools()
    if not LEVEL.liquid then return end

    local prob = 70  -- FIXME

    each island in cave.islands do
      if rand.odds(prob) then
        render_liquid_area(island)
      end
    end
  end


  local function add_sky_rects()
    for sx = R.sx1, R.sx2 do
    for sy = R.sy1, R.sy2 do
      local S = SEEDS[sx][sy]

      if S.room == R then
        local rect =
        {
          x1 = S.x1, y1 = S.y1
          x2 = S.x2, y2 = S.y2
        }

        table.insert(R.sky_rects, rect)
      end
    end -- sx, sy
    end
  end


  ---| Simple_render_cave |---
  
  create_delta_map()

  if true then
    R.walkway_mat = choose_tex(R.floor_mat, R.theme.naturals or THEME.naturals)
  end

--!!!! FIXME  add_liquid_pools()

  for x = 1, info.W do
  for y = 1, info.H do
    render_cell(x, y)
  end
  end

  each A in info.floors do
    determine_spots(A)
  end

  if R.is_outdoor then
    add_sky_rects()
  end
end



function Simple_fill_lakes(R)
  local info = R.cave_info
  local cave = info.cave


  local function add_lake(id, reg)

    -- FIXME: if reg.size < 16 then emptify_region()

    local LAKE =
    {
      liquid = true

      region = reg

      cx1 = reg.x1
      cy1 = reg.y1
      cx2 = reg.x2
      cy2 = reg.y2
    }

    table.insert(info.lakes, LAKE)

    for x = LAKE.cx1, LAKE.cx2 do
    for y = LAKE.cy1, LAKE.cy2 do
      if cave.flood[x][y] == id then
        info.blocks[x][y] = LAKE
      end
    end
    end
  end


  local function handle_island(id, reg)

    -- TODO: if large, keep as island and add bridge to nearby ground

    add_lake(id, reg)
  end


  ---| Simple_fill_lakes |---

  info.lakes = {}

  if info.liquid_mode != "lake" then return end

  -- determine region id for the main walkway
  local p1 = R.point_list[1]

  local path_id = cave.flood[p1.x][p1.y]

  each id,reg in cave.regions do
    if (id > 0) then
      add_lake(id, reg)
    end

    if (id < 0) and (id != path_id) then
      handle_island(id, reg)
    end
  end
end



function Simple_lake_fences(R)
  local info = R.cave_info

  local function install_fence_post(cx1, cy1, cx2, cy2, dir, along_dir, i, deep)
    if along_dir == 6 then
      cx1 = cx1 + (i - 1)
      cx2 = cx1
    else
      cy1 = cy1 + (i - 1)
      cy2 = cy1
    end

        if dir == 2 then cy2 = cy1 + (deep - 1)
    elseif dir == 8 then cy1 = cy2 - (deep - 1)
    elseif dir == 4 then cx2 = cx1 + (deep - 1)
    elseif dir == 6 then cx1 = cx2 - (deep - 1)
    end

    for x = cx1, cx2 do
    for y = cy1, cy2 do
      info.blocks[x][y] = info.fence
    end
    end
  end


  local function try_fence_run(S, dir)
    if not S.lake_fences then S.lake_fences = {} end

    -- already done?
    if S.lake_fences[dir] then return end

    local along_dir = geom.vert_sel(dir, 6, 8)

    local count = 1

    local S1 = S
    local S2 = S:neighbor(along_dir)

    while S2 do
      if S2.room != R then break; end

      assert(not (S2.lake_fences and S2.lake_fences[dir]))

      if not S2:need_lake_fence(dir) then break; end

      if not S2.lake_fences then S2.lake_fences = {} end

      count = count + 1

      S2 = S2:neighbor(along_dir)
    end

    --- OK, install it ---

    for i = 1, count do
      local N = S:neighbor(along_dir, i - 1)

      N.lake_fences[dir] = true  -- prevent visiting again
    end

    local S2 = S:neighbor(along_dir, count - 1)

    local cx1 = 1 + (S.sx - R.sx1) * 4
    local cy1 = 1 + (S.sy - R.sy1) * 4

    local cx2 = 1 + (S2.sx - R.sx1) * 4 + 3
    local cy2 = 1 + (S2.sy - R.sy1) * 4 + 3

    assert(cx2 > cx1 and cy2 > cy1)

    -- starting depth
    local deep = rand.sel(50, 1, 2)

    for i = 1, count * 4 do
      install_fence_post(cx1, cy1, cx2, cy2, dir, along_dir, i, deep)

      -- pick next depth
          if deep == 1 then deep = rand.index_by_probs({ 50, 45,  5})
      elseif deep == 2 then deep = rand.index_by_probs({ 35, 50, 15})
      elseif deep == 3 then deep = rand.index_by_probs({  5, 45, 50})
      end
    end
  end


  --| Simple_lake_fences |--

  if info.liquid_mode != "lake" then return end

  local FENCE =  
  {
    fence = true

    -- floor_h
  }

  info.fence = FENCE

  for sx = R.sx1, R.sx2 do
  for sy = R.sy1, R.sy2 do
    local S = SEEDS[sx][sy]

    if S.room != R then continue end

    for dir = 2,8,2 do
      if S:need_lake_fence(dir) then
        try_fence_run(S, dir)
      end
    end

  end -- sx, sy
  end
end



function Simple_outdoor_borders(R)
  local info = R.cave_info

  local f_mat = assert(R.wall_mat)
  local f_h   = R.min_floor_h - 256


  local function sky_border(S, dir)
    local x1, y1 = S.x1, S.y1
    local x2, y2 = S.x2, S.y2

    if dir == 2 then y2 = y1 ; y1 = y1 - 16 end
    if dir == 8 then y1 = y2 ; y2 = y2 + 16 end
    if dir == 4 then x2 = x1 ; x1 = x1 - 16 end
    if dir == 6 then x1 = x2 ; x2 = x2 + 16 end

    local brush = Brush_new_quad(x1, y1, x2, y2)
    table.insert(brush, { t=f_h, reachable=true })
    Brush_set_mat(brush, f_mat, f_mat)
    brush_helper(brush)

    Build_sky_quad(x1, y1, x2, y2, f_h + 4)
  end


  ---| Simple_outdoor_borders |---

  if not (info.liquid_mode == "lake" or
          info.sky_mode == "low_wall")
  then
    return
  end

  for sx = R.sx1, R.sx2 do
  for sy = R.sy1, R.sy2 do
    local S = SEEDS[sx][sy]

    if S.room != R then continue end

    for dir = 2,8,2 do
      if not S:neighbor(dir) then
        sky_border(S, dir)
      end
    end
  end  -- sx, sy
  end
end



function Simple_decorations(R)
  --|
  --| add torches (etc)
  --|

  local info = R.cave_info
  local cave = info.cave


  local locs = {}


  local function block_is_bounded(x, y, A, dir)
    local nx, ny = geom.nudge(x, y, dir)

    if not cave:valid_cell(nx, ny) then return true end

    local N = info.blocks[nx][ny]

    if not (N and N.floor_h) then return true end
    if N.wall or N.fence then return true end

    if N.liquid then return false end

    if N.floor_h < (A.floor_h + 78) then return false end

    -- check opposite side

    nx, ny = geom.nudge(x, y, 10 - dir)

    if not cave:valid_cell(nx, ny) then return false end

    N = info.blocks[nx][ny]

    return (N == A)
  end


  local function usable_corner(x, y)
    local A = info.blocks[x][y]

    if not (A and A.floor_h) then return false end
    if A.wall or A.fence or A.liquid then return false end
    if A.goal_type then return false end

    -- analyse N/S/E/W...
    local got_dir = {}

    for dir = 2,8,2 do
      if block_is_bounded(x, y, A, dir) then
        got_dir[dir] = 1
      end
    end

    if table.size(got_dir) != 2 then return false end

    local v_dir = got_dir[2] or got_dir[8]
    local h_dir = got_dir[4] or got_dir[6]

    if not (v_dir and h_dir) then return false end

    -- check corner cell
    local dx = sel(h_dir == 4, -1, 1)
    local dy = sel(v_dir == 2, -1, 1)

    if info.blocks[x + dx][y + dy] != A then return false end

    -- OK!
    return true
  end


  local function find_corner_locs()
    for x = 2, info.W - 1 do
    for y = 2, info.H - 1 do
      if usable_corner(x, y) then
        table.insert(locs, { cx=x, cy=y })    


      end
    end
    end
  end


  local function select_torch()
    local tab = R.theme.torches or THEME.cave_torches

    if not tab then return end

    return rand.key_by_probs(tab)
  end


  local function add_torch(x, y, torch_ent)
    local A = info.blocks[x][y]
    assert(A and A.floor_h)

    local mx = info.x1 + (x-1) * 64 + 32
    local my = info.y1 + (y-1) * 64 + 32

    entity_helper(torch_ent, mx, my, A.floor_h, { light=192, factor=1.2 })

    -- remember bbox, prevent placing items/monsters here

    local DECOR =
    {
      x1 = mx - 32, x2 = mx + 32
      y1 = my - 32, y2 = my + 32
    }

    if not A.decorations then
      A.decorations = {}
    end

    table.insert(A.decorations, DECOR)
  end


  local function place_torches_in_corners()
    local torch_ent = select_torch()

    if not torch_ent then return end

    find_corner_locs()

    local prob = 11

    each loc in locs do
      if rand.odds(prob) then
        add_torch(loc.cx, loc.cy, torch_ent)
      end
    end
  end


  ---| Simple_decorations |---

  if info.torch_mode != "none" then
    place_torches_in_corners()
  end

end



function Simple_decide_properties(R)
  local info = R.cave_info

  local   STEP_MODES = { walkway=25, up=15, down=10, mixed=65 }
  local LIQUID_MODES = { none=20, some=80, lake=80 }

  -- decide liquid mode
  if not LEVEL.liquid then
    info.liquid_mode = "none"
    STEP_MODES.walkway = nil
  else
    if not R.is_outdoor then
      LIQUID_MODES.lake = nil
    end

    info.liquid_mode = rand.key_by_probs(LIQUID_MODES)
  end

  -- decide step mode
  if info.liquid_mode == "lake" then
    STEP_MODES.walkway = nil
  end

  info.step_mode = rand.key_by_probs(STEP_MODES)

  -- decide sky mode
  if R.is_outdoor then
    info.sky_mode = rand.sel(50, "high_wall", "low_wall")
  else
    info.sky_mode = rand.sel(30, "some", "none")
  end

  -- decide torch mode
  local prob = 95

  if info.liquid_mode != "none" then
    prob = sel(info.step_mode == "walkway", 65, 30)
  end

  if not LEVEL.is_dark then
    if R.is_outdoor or info.sky_mode != "none" then
      prob = 0
    end
  end

  info.torch_mode = rand.sel(prob, "some", "none")

  -- extra health for damaging liquid
  if LEVEL.liquid and LEVEL.liquid.damage then
    if info.liquid_mode != "none" then
      R.hazard_health = R.hazard_health + R.svolume
    end
  end

  gui.debugf("Cave properties in %s\n", R:tostr())
  gui.debugf("    step_mode : %s\n", info.step_mode);
  gui.debugf("  liquid_mode : %s\n", info.liquid_mode);
  gui.debugf("     sky_mode : %s\n", info.sky_mode);
  gui.debugf("   torch_mode : %s\n", info.torch_mode);
end



function Simple_cave_or_maze(R)
  R.cave_info = {}

  Simple_decide_properties(R)
  Simple_generate_cave(R)

  Simple_lake_fences(R)
  Simple_fill_lakes(R)
  Simple_outdoor_borders(R)

  Simple_create_areas(R)
  Simple_bunch_areas(R, "liquid")
  Simple_bunch_areas(R, "sky")

  Simple_floor_heights(R, R.entry_h)
  Simple_decorations(R)

  Simple_render_cave(R)
end

