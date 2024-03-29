----------------------------------------------------------------
--  CAVE / MAZE GENERATION
----------------------------------------------------------------
--
--  Oblige Level Maker
--
--  Copyright (C) 2009-2012 Andrew Apted
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
--
--  The cave algorithm used here in the generate() function was
--  described by Jim Babcock in his article: "Cellular Automata
--  Method for Generating Random Cave-Like Levels".
--
----------------------------------------------------------------

--[[ *** CLASS INFORMATION ***

class CAVE
{
  w, h   -- width and height (in cells)
  
  cells : array_2D(number)  -- > 0 means solid
                            -- < 0 means empty

  flood : array_2D(number)  -- contiguous areas have the same value
                            -- (positive for solid, negative for empty)

  empty_id  -- the main empty area in the flood_fill
            -- this is set by the validate_conns() method

  islands : list(CAVE)

  regions : table[id] -> REGION

  square  -- if set, render() method won't smooth out the 64x64 blocks
}


class REGION
{
  id : number

  x1, y1, x2, y2  -- bounding box (in cell coordinates)

  size : number of cells
}


--------------------------------------------------------------]]


CAVE_CLASS = {}


function CAVE_CLASS.new(w, h)
  local cave = { w=w, h=h }
  table.set_class(cave, CAVE_CLASS)
  cave.cells = table.array_2D(w, h)
  return cave
end


function CAVE_CLASS.blank_copy(cave)
  return CAVE_CLASS.new(cave.w, cave.h)
end


function CAVE_CLASS.valid_cell(cave, x, y)
  return (1 <= x and x <= cave.w) and (1 <= y and y <= cave.h)
end


function CAVE_CLASS.get(cave, x, y)
  return cave.cells[x][y]
end


function CAVE_CLASS.set(cave, x, y, val)
  cave.cells[x][y] = val
end


function CAVE_CLASS.fill(cave, x1,y1, x2,y2, val)
  for x = x1, x2 do
  for y = y1, y2 do
    cave.cells[x][y] = val
  end
  end
end


function CAVE_CLASS.set_all(cave, val)
  cave:fill(1, 1, cave.w, cave.h, val)
end


function CAVE_CLASS.negate(cave, x1,y1, x2,y2)
  if not x1 then
    x1, x2 = 1, cave.w
    y1, y2 = 1, cave.h
  end

  for x = x1, x2 do
  for y = y1, y2 do
    if cave.cells[x][y] then
      cave.cells[x][y] = - cave.cells[x][y]
    end
  end
  end

  return cave
end


function CAVE_CLASS.copy(cave)
  -- only copies 'w', 'h' and 'cells' members

  local newbie = cave:blank_copy()

  for x = 1, cave.w do
  for y = 1, cave.h do
    newbie.cells[x][y] = cave.cells[x][y]
  end
  end

  return newbie
end


function CAVE_CLASS.dump(cave, title)
  if title then
    gui.debugf("%s\n", title)
  end

  for y = cave.h,1,-1 do
    local line = "@c| ";
    
    for x = 1,cave.w do
      local ch = " "
      local cell = cave.cells[x][y]

      if  cell == 0      then ch = "/" end
      if (cell or 0) > 0 then ch = "#" end
      if (cell or 0) < 0 then ch = "." end

      line = line .. ch
    end

    gui.debugf("%s\n", line)
  end

  gui.debugf("\n")
end


function CAVE_CLASS.union(cave, other)
  local W = math.min(cave.w, other.w)
  local H = math.min(cave.h, other.h)

  for x = 1, W do
  for y = 1, H do
    if ( cave.cells[x][y] or 0) < 0 and
       (other.cells[x][y] or 0) > 0
    then
      cave.cells[x][y] = other.cells[x][y]
    end
  end
  end
end


function CAVE_CLASS.intersection(cave, other)
  local W = math.min(cave.w, other.w)
  local H = math.min(cave.h, other.h)

  for x = 1, W do
  for y = 1, H do
    if ( cave.cells[x][y] or 0) > 0 and
       (other.cells[x][y] or 0) < 0
    then
      cave.cells[x][y] = other.cells[x][y]
    end
  end
  end
end


function CAVE_CLASS.subtract(cave, other)
  local W = math.min(cave.w, other.w)
  local H = math.min(cave.h, other.h)

  local empty_id = cave.empty_id or -1

  for x = 1, W do
  for y = 1, H do
    if ( cave.cells[x][y] or 0) > 0 and
       (other.cells[x][y] or 0) > 0
    then
      cave.cells[x][y] = empty_id
    end
  end
  end
end


function CAVE_CLASS.generate(cave, solid_prob)

  -- The initial contents of the cave form a map where the cave
  -- will be generated.  The following values can be used:
  --
  --    nil : never touched
  --     -1 : forced off
  --      0 : computed normally
  --     +1 : forced on
  --
  -- Result elements can be: nil, -1 or +1.
  --

-- FIXME: support -2, +2 as 'forced' on, -1,+1 as initial values

  solid_prob = solid_prob or 40

  local W = cave.w
  local H = cave.h

  local map  = cave.cells

  -- these arrays only use 0 and 1 as values
  local work = table.array_2D(W, H)
  local temp = table.array_2D(W, H)

  -- populate initial map
  for x = 1, W do
  for y = 1, H do
    if not map[x][y] or map[x][y] < 0 then
      work[x][y] = 0
    elseif map[x][y] > 0 then
      work[x][y] = 1
    else
      work[x][y] = rand.sel(solid_prob, 1, 0)
    end
  end
  end

  local function calc_new(x, y, loop)
    if not map[x][y] then return 0 end
    if map[x][y] > 0 then return 1 end
    if map[x][y] < 0 then return 0 end

    if x == 1 or x == W or y == 1 or y == H then
      return work[x][y]
    end

    local neighbors = 0
    for nx = x-1,x+1 do
    for ny = y-1,y+1 do
      neighbors = neighbors + work[nx][ny]
    end
    end

    if neighbors >= 5 then return 1 end

    if loop >= 5 then return 0 end

    if x <= 2 or x >= W-1 or y <= 2 or y >= H-1 then return 0 end

    -- check larger area
    local neighbors = 0
    for nx = x-2,x+2 do
    for ny = y-2,y+2 do
      if math.abs(x-nx) == 2 and math.abs(y-ny) == 2 then
        -- skip the corners of the 5x5 block
      else
        neighbors = neighbors + work[nx][ny]
      end
    end
    end

    if neighbors <= 2 then return 1 end

    return 0
  end

  -- perform the cellular automation steps
  for loop = 1,7 do
    for x = 1, W do
    for y = 1, H do
      temp[x][y] = calc_new(x, y, loop)
    end
    end

    work, temp = temp, work
  end

  -- convert values for the result
  for x = 1, W do
  for y = 1, H do
    if map[x][y] == 0 then
      work[x][y] = sel(work[x][y] > 0, 1, -1)
    else
      work[x][y] = map[x][y]
    end
  end
  end

  cave.cells = work
end


function CAVE_CLASS.gen_empty(cave)
  
  -- this is akin to generate(), but making all target cells empty

  local W = cave.w
  local H = cave.h

  local cells = cave.cells

  for x = 1, W do
  for y = 1, H do
    if not cells[x][y] then
      -- skip it
    elseif cells[x][y] > 0 then
      cells[x][y] = 1
    else
      cells[x][y] = -1
    end
  end
  end

  return cave
end


function CAVE_CLASS.dump_regions(cave)
  if not cave.regions then
    gui.debugf("No region info (flood_fill not called yet)\n")
    return
  end

  gui.debugf("Regions:\n")

  each id,REG in cave.regions do
    gui.debugf("  %+4d : (%d %d) .. (%d %d) size:%d\n",
               REG.id, REG.x1, REG.y1, REG.x2, REG.y2, REG.size)
  end

  gui.debugf("Empty regions: %d (with %d cells)\n", cave.empty_regions, cave.empty_cells)
  gui.debugf("Solid regions: %d (with %d cells)\n", cave.solid_regions, cave.solid_cells)
end


function CAVE_CLASS.flood_fill(cave)
  -- generate the 'flood' member, an array where each contiguous region
  -- has a unique id.  Empty areas are negative, solid areas are positive,
  -- and everything else is NIL.
  --
  -- This also creates the 'regions' table.

  local W = cave.w
  local H = cave.h

  local cells = cave.cells
  local flood = table.array_2D(W, H)

  local solid_id =  1
  local empty_id = -1

  local next_points = {}

  local function flood_point(x, y)
    -- spread value from this cell to neighbors

    local A = flood[x][y]
    assert(A)

    for dir = 2,8,2 do
      local nx, ny = geom.nudge(x, y, dir)
      if nx >= 1 and nx <= W and ny >= 1 and ny <= H then
        local B = flood[nx][ny]

        if B and ((A > 0 and A < B) or (A < 0 and A > B)) then
          flood[nx][ny] = A
          table.insert(next_points, { x=nx, y=ny })
        end
      end
    end
  end


  local function update_info(x, y)
    local id = flood[x][y]

    if not id then return end

    assert(id != 0)

    if id < 0 then
      cave.empty_cells = cave.empty_cells + 1
    else
      cave.solid_cells = cave.solid_cells + 1
    end

    local REG = cave.regions[id]

    if not REG then
      REG =
      {
        id = id
        x1 = x, y1 = y
        x2 = x, y2 = y
        size = 0
      }

      cave.regions[id] = REG

      if id < 0 then
        cave.empty_regions = cave.empty_regions + 1
      else
        cave.solid_regions = cave.solid_regions + 1
      end
    end

    if x < REG.x1 then REG.x1 = x end
    if y < REG.y1 then REG.y1 = y end
    if x > REG.x2 then REG.x2 = x end
    if y > REG.y2 then REG.y2 = y end

    REG.size = REG.size + 1
  end


  -- initial setup

  for x = 1, W do
  for y = 1, H do
    if not cells[x][y] then
      -- ignore it
    elseif cells[x][y] < 0 then
      flood[x][y] = empty_id ; empty_id = empty_id - 1
    else
      flood[x][y] = solid_id ; solid_id = solid_id + 1
    end
  end
  end

  -- perform the flood-fill

  for x = 1, W do
  for y = 1, H do
    if flood[x][y] then
      flood_point(x, y)
    end
  end
  end

  while #next_points > 0 do
    local np_list = next_points ; next_points = {}

    each P in np_list do
      flood_point(P.x, P.y)
    end
  end

  -- create information for each region

  cave.regions = {}

  cave.empty_cells = 0
  cave.solid_cells = 0
  cave.empty_regions = 0
  cave.solid_regions = 0

  for x = 1, W do
  for y = 1, H do
    update_info(x, y)
  end
  end

  cave.flood = flood

      cave:dump_regions()
end


function CAVE_CLASS.validate_conns(cave, point_list)

  -- checks that all connections can reach each other.

  local empty_id = nil

  if not cave.flood then
    cave:flood_fill()
  end

  each P in point_list do
    if (cave.flood[P.x][P.y] or 0) >= 0 then
      -- not valid : the cell is solid or absent
      return false
    end

    local reg = cave.flood[P.x][P.y]

    if not empty_id then
      empty_id = reg
    elseif empty_id != reg then
      -- not valid : the empty areas are disjoint
      return false
    end
  end -- P

  cave.empty_id = empty_id

  return true
end


function CAVE_CLASS.solidify_pockets(cave)
  -- this removes the empty areas which are surrounded by solid
  -- (i.e. not part of the main walk area).

  local function find_one()
    each id,REG in cave.regions do
      if id < 0 and id != cave.empty_id then
        return id
      end
    end

    -- nothing found
    return nil
  end

  while true do
    local pocket_id = find_one()

    if not pocket_id then break end

    local REG = cave.regions[pocket_id]
    assert(REG)

    -- solidify the cells
    for x = REG.x1, REG.x2 do
    for y = REG.y1, REG.y2 do
      if cave.flood[x][y] == pocket_id then
        cave.cells[x][y] = 1
        cave.flood[x][y] = nil
      end
    end
    end

    -- remove the region info
    cave.regions[pocket_id] = nil
  end
end


function CAVE_CLASS.copy_island(cave, reg_id)
  local W = cave.w
  local H = cave.h

  local flood = assert(cave.flood)

  local island = cave:blank_copy()

  for x = 1, W do
  for y = 1, H do
    local val = flood[x][y]
    if val == nil then
      -- nothing to copy
    else
      island.cells[x][y] = sel(val == reg_id, 1, -1)
    end
  end
  end

  island:dump("Island for " .. tostring(reg_id))

  return island
end


function CAVE_CLASS.find_islands(cave)
  
  -- an "island" is contiguous solid area which never touches NIL

  local islands = {}

  local W = cave.w
  local H = cave.h

  if not cave.flood then
    cave:flood_fill()
  end

  local flood = cave.flood

  -- scan the cave, determine which regions are islands

  -- a table mapping region ids to a string value: "maybe" if could be
  -- an island, and "no" when definitely not an island. 
  local potentials = {}

  for x = 1, W do
  for y = 1, H do
    local reg = flood[x][y]
    if (reg or 0) > 0 then

      if not potentials[reg] then
        potentials[reg] = "maybe"
      end

      if x == 1 or x == W or y == 1 or y == H then
        potentials[reg] = "no"
      end

      if potentials[reg] != "no" then
        for side = 2,8,2 do
          local nx, ny = geom.nudge(x, y, side)
          if cave:valid_cell(nx, ny) and flood[nx][ny] == nil then
            potentials[reg] = "no"
            break;
          end
        end
      end

    end
  end -- x, y
  end

  -- create the islands

  for reg,pot in pairs(potentials) do
    if pot == "maybe" then
      table.insert(islands, cave:copy_island(reg))
    end
  end

  cave.islands = islands
end


function CAVE_CLASS.validate_size(cave)
  assert(cave.empty_id)

  local empty_reg = cave.regions[cave.empty_id]
  assert(empty_reg)

  local W = cave.w
  local H = cave.h

  local cw = empty_reg.x2 - empty_reg.x1 + 1
  local ch = empty_reg.y2 - empty_reg.y1 + 1

  if cw < W / 2 then return false end
  if ch < H / 2 then return false end

  -- volume check
  if cw * ch < W * H / 2.5 then return false end

  return true  -- OK --
end


function CAVE_CLASS.grow(cave, keep_edges)
  -- grow the cave : it will have more solids, less empties.
  -- nil cells are not affected.

  local W = cave.w
  local H = cave.h

  local work = table.array_2D(W, H)
  local cells = cave.cells

  local function value_for_spot(x, y)
    local val = cells[x][y]
    local hit_edge

    for dir = 2,8,2 do
      local nx, ny = geom.nudge(x, y, dir)

      if not cave:valid_cell(nx, ny) or not cells[nx][ny] then
        hit_edge = true
      elseif cells[nx][ny] > 0 then
        val = cells[nx][ny]
      end
    end

    if keep_edges and hit_edge then
      return cells[x][y]
    end

    return val
  end

  for x = 1, W do
  for y = 1, H do
    if cells[x][y] then
      work[x][y] = value_for_spot(x, y)
    end
  end
  end

  cave.cells = work
end


function CAVE_CLASS.grow8(cave, keep_edges)
  -- like grow() method but expands in all 8 directions

  local W = cave.w
  local H = cave.h

  local work = table.array_2D(W, H)
  local cells = cave.cells

  local function value_for_spot(x, y)
    local val = cells[x][y]
    local hit_edge

    for dir = 1,9 do if dir != 5 then
      local nx, ny = geom.nudge(x, y, dir)

      if not cave:valid_cell(nx, ny) or not cells[nx][ny] then
        hit_edge = true
      elseif cells[nx][ny] > 0 then
        val = cells[nx][ny]
      end
    end end -- dir

    if keep_edges and hit_edge then
      return cells[x][y]
    end

    return val
  end

  for x = 1, W do
  for y = 1, H do
    if cells[x][y] then
      work[x][y] = value_for_spot(x, y)
    end
  end
  end

  cave.cells = work
end


function CAVE_CLASS.shrink(cave, keep_edges)
  -- shrink the cave : it will have more empties, less solids.
  -- when 'keep_edges' is true, cells at edges are not touched.
  -- nil cells are not affected.

  local W = cave.w
  local H = cave.h

  local work = table.array_2D(W, H)
  local cells = cave.cells

  local function value_for_spot(x, y)
    local val = cells[x][y]
    local hit_edge

    for dir = 2,8,2 do
      local nx, ny = geom.nudge(x, y, dir)
    
      if not cave:valid_cell(nx, ny) or not cells[nx][ny] then
        hit_edge = true
      elseif cells[nx][ny] < 0 then
        val = cells[nx][ny]
      end
    end

    if keep_edges and hit_edge then
      return cells[x][y]
    end

    return val
  end

  for x = 1, W do
  for y = 1, H do
    if cells[x][y] then
      work[x][y] = value_for_spot(x, y)
    end
  end
  end

  cave.cells = work
end


function CAVE_CLASS.shrink8(cave, keep_edges)
  -- like shrink() method but checks all 8 directions

  local W = cave.w
  local H = cave.h

  local work = table.array_2D(W, H)
  local cells = cave.cells

  local function value_for_spot(x, y)
    local val = cells[x][y]
    local hit_edge

    for dir = 1,9 do if dir != 5 then
      local nx, ny = geom.nudge(x, y, dir)
    
      if not cave:valid_cell(nx, ny) or not cells[nx][ny] then
        hit_edge = true
      elseif cells[nx][ny] < 0 then
        val = cells[nx][ny]
      end
    end end -- dir

    if keep_edges and hit_edge then
      return cells[x][y]
    end

    return val
  end

  for x = 1, W do
  for y = 1, H do
    if cells[x][y] then
      work[x][y] = value_for_spot(x, y)
    end
  end
  end

  cave.cells = work
end


function CAVE_CLASS.remove_dots(cave)
  -- removes isolated cells (solid or empty) from the cave.
  -- diagonal cells are NOT checked.

  local W = cave.w
  local H = cave.h

  local cells = cave.cells

  local function is_isolated(x, y, val)
    for dir = 2,8,2 do
      local nx, ny = geom.nudge(x, y, dir)

      if not cave:valid_cell(nx, ny) or not cells[nx][ny] then
        -- ignore it
      elseif cells[nx][ny] == val then
        return false
      end
    end

    return true
  end

  for x = 1, W do
  for y = 1, H do
    local val = cells[x][y]

    if val and val != 0 and is_isolated(x, y, val) then
      local dx = sel(x > W/2, -1, 1)
      cells[x][y] = cells[x+dx][y]
    end
  end
  end
end


function CAVE_CLASS.is_land_locked(cave, x, y)
  if x <= 1 or x >= cave.w or y <= 1 or y >= cave.h then
    return false
  end

  local cells = cave.cells

  for dx = -1, 1 do
  for dy = -1, 1 do
    if (cells[x+dx][y+dy] or 0) < 0 then
      return false
    end
  end
  end

  return true
end


function CAVE_CLASS.is_empty_locked(cave, x, y)
  if x <= 1 or x >= cave.w or y <= 1 or y >= cave.h then
    return false
  end

  local cells = cave.cells

  for dx = -1,1 do
  for dy = -1,1 do
    if (cells[x+dx][y+dy] or 0) >= 0 then
      return false
    end
  end
  end

  return true
end


function CAVE_CLASS.distance_map(cave, ref_points)
  assert(cave.flood)
  assert(cave.empty_id)

  local W = cave.w
  local H = cave.h

  local work = table.array_2D(W, H)
  local flood = cave.flood

  local next_points = {}

  local function flood_point(x, y)

    -- spread this distance into neighbor cells
    local dist = work[x][y] + 1

    for side = 2,8,2 do
      local nx, ny = geom.nudge(x, y, side)
      if nx >= 1 and nx <= W and ny >= 1 and ny <= H then
        local F = flood[nx][ny]
        local W =  work[nx][ny]

        if F == cave.empty_id and (not W or W > dist) then
          flood[nx][ny] = dist
          table.insert(next_points, { x=nx, y=ny })
        end
      end
    end
  end

  -- perform the fill

  for _,P in ipairs(ref_points) do
    work[P.x][P.y] = 0
    flood_point(P.x, P.y)
  end

  while #next_points > 0 do
    local np_list = next_points ; next_points = {}

    for _,P in ipairs(np_list) do
      flood_point(P.x, P.y)
    end
  end

  return work
end


function CAVE_CLASS.furthest_point(cave, ref_points)
  local dist_map = cave:distance_map(ref_points)

  local best_x, best_y
  local best_dist = 9e9

  for x = 1, W do
  for y = 1, H do
    local dist = dist_map[x][y]
    if dist and dist < (best_dist+3) then

      -- prefer away from edges
      if x == 1 or x == W then dist = dist + 0.1 end
      if y == 1 or y == H then dist = dist + 0.2 end

      -- prefer a spot away from the wall
      if cave:is_empty_locked(x, y) then
        dist = dist - 2.4
      end

      if dist < best_dist then
        best_x, best_y = x, y
        best_dist = dist
      end

    end
  end  -- x, y
  end

  return best_x, best_y  -- could be nil !
end




----------------------------------------------------------------
--  MAZE STUFF
----------------------------------------------------------------


function CAVE_CLASS.maze_generate(maze)

  -- Generates a maze in the current object.
  --
  -- The initial contents should form a map where the maze will be
  -- generated.  The cells next to walls should be set to 1 and
  -- areas which must remain clear (in front of doors) set to -1.
  --
  -- These values can be used:
  --
  --    nil : never touched
  --     -1 : forced off
  --      0 : computed normally
  --     +1 : forced on
  --
  -- Result elements can be: nil, -1 or +1.
  --

  local W = maze.w
  local H = maze.h

  local cells = maze.cells


  local function valid_and_free(x, y)
    return maze:valid_cell(x, y) and cells[x][y] == 0
  end


  local function how_far_can_move(x, y, dir)
    -- when start is in open space, require all neighbors to be open too
    if cells[x][y] == 0 then
      for side = 1,9 do
        local nx, ny = geom.nudge(x, y, side)
        if not valid_and_free(nx, ny) then return 0 end
      end
    end

    local len = 0

    while len < 5 do
      -- check the next spot is free, and also the cells on either side
      x, y = geom.nudge(x, y, dir)

      if not valid_and_free(x, y) then break; end
      
      local ax, ay = geom.nudge(x, y, geom.RIGHT[dir])
      local bx, by = geom.nudge(x, y, geom.LEFT [dir])

      if not valid_and_free(ax, ay) then break; end
      if not valid_and_free(bx, by) then break; end

      len = len + 1
    end

    -- don't touch the far wall
    len = len -1

    -- usually move two steps, occasionally more
    if len >= 3 and rand.odds(75) then len = 2 end
    if len >= 4 and rand.odds(95) then len = 3 end

    assert(len <= 4)

    return len
  end


  local function is_edge(x, y, dir)
    x, y = geom.nudge(x, y, 10-dir)

    if not maze:valid_cell(x, y) then return true end

    if not cells[x][y] then return true end

    return false
  end


  local function pick_start()
    -- TODO: optimise this (how ?)

    local middles = {}
    local edges   = {}

    for x = 1, W do
    for y = 1, H do
      if (cells[x][y] or 0) > 0 or 
         (cells[x][y] == 0 and (table.empty(middles) or rand.odds(2)))
      then
        for dir = 2,8,2 do
          local len = how_far_can_move(x, y, dir)

          if len >= 2 then
            local SPOT = { x=x, y=y, dir=dir, len=len }

            if is_edge(x, y, dir) then
              table.insert(edges, SPOT)
            else
              table.insert(middles, SPOT)
            end
          end
        end
      end
    end -- x, y
    end

    -- we much prefer starting at an edge
    if #edges > 0 then
      return rand.pick(edges)
    end

    if #middles > 0 then
      return rand.pick(middles)
    end

    return nil
  end


  local function trace_next(p)
    cells[p.x][p.y] = 1

    for i = 1,p.len do
      p.x, p.y = geom.nudge(p.x, p.y, p.dir)

      cells[p.x][p.y] = 1
    end

    -- set how far we can move in each direction
    local lens = {}

    for dir = 2,8,2 do
      if dir != p.dir then
        local len = how_far_can_move(p.x, p.y, dir)

        if len > 0 then
          lens[dir] = len 
        end
      end
    end

    -- nowhere else to go?
    if table.empty(lens) then return false end

    for loop = 1,20 do
      local dir = rand.dir()

      if dir == p.dir and rand.odds(60) then
        dir = 5  -- i.e. continue
      end

      if lens[dir] then
        p.dir = dir
        p.len = lens[dir]
        return true
      end
    end

    return false
  end


  local function tidy_up()
    for x = 1, W do
    for y = 1, H do
      if cells[x][y] == 0 then
         cells[x][y] = -1
      end
    end
    end
  end


  ---| maze_generate |---

  while true do
    -- choose starting spot for a wall run
    local pos = pick_start()

    -- stop if nothing is possible
    if not pos then break; end

    -- occasionally stop short, but usually go as far as possible
    local max_steps = rand.irange(3, 40)

    for loop = 1,max_steps do
      if not trace_next(pos) then break; end
    end
  end

  tidy_up()
end



function CAVE_CLASS.maze_render(maze, brush_func, data)
  local W = maze.w
  local H = maze.h

  local cells = maze.cells


  local function visit_cell(x, y)
    if (cells[x][y] or 0) <= 0 then return; end

    local bx = maze.base_x + (x - 1) * 64
    local by = maze.base_y + (y - 1) * 64

    -- most basic method (mostly for debugging)
    if true then
      brush_func(data,
      {
        { x=bx+64, y=by }
        { x=bx+64, y=by+64 }
        { x=bx,    y=by+64 }
        { x=bx,    y=by }
      })

      return;
    end

    -- FIXME: better method, find "wall spans"
  end


  ---| maze_render |---

  for x = 1, W do
  for y = 1, H do
    visit_cell(x, y)
  end
  end
end



function Maze_test()
  local SIZE = 15

  for loop = 1,20 do
    local maze = CAVE_CLASS.new(SIZE, SIZE)

    -- solid on outside, empty in middle
    maze:fill(1,1, SIZE,SIZE,     1)
    maze:fill(2,2, SIZE-1,SIZE-1, 0)

    -- doorways at top and bottom
    local d1 = rand.irange(2,SIZE-3)
    local d2 = rand.irange(2,SIZE-3)

    maze:fill(d1,1,      d1+2,3,    -1)
    maze:fill(d2,SIZE-2, d2+2,SIZE, -1)

    maze:maze_generate()

    gui.debugf("MAZE TEST %d\n\n", loop)

    maze:dump()
  end
end

