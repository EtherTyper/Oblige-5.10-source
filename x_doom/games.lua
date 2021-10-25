----------------------------------------------------------------
--  GAME DEFINITION : DOOM, DOOM II (etc)
----------------------------------------------------------------
--
--  Oblige Level Maker
--
--  Copyright (C) 2006-2013 Andrew Apted
--  Copyright (C)      2011 Chris Pisarczyk
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

DOOM  = { }  -- common stuff

DOOM1 = { }  -- game specific stuff
DOOM2 = { }  --

TNT      = { }
PLUTONIA = { }
FREEDOOM = { }


-- skin tables
DOOM .SKINS = { }
DOOM1.SKINS = { }
DOOM2.SKINS = { }

TNT.SKINS      = { }
PLUTONIA.SKINS = { }
FREEDOOM.SKINS = { }


-- group tables
DOOM .GROUPS = { }
DOOM1.GROUPS = { }
DOOM2.GROUPS = { }

TNT.GROUPS      = { }
PLUTONIA.GROUPS = { }
FREEDOOM.GROUPS = { }


----------------------------------------------------------------

-- load in all the other definition files...

require "entities"
require "monsters"
require "weapons"
require "pickups"

require "params"
require "materials"
require "themes"
require "levels"
require "resources"


----------------------------------------------------------------

OB_GAMES["doom2"] =
{
  label = "Doom 2"

  priority = 99  -- keep at top

  format = "doom"

  tables =
  {
    DOOM, DOOM2
  }

  hooks =
  {
    get_levels = DOOM2.get_levels
    end_level  = DOOM2.end_level
    all_done   = DOOM2.all_done
  }
}


UNFINISHED["doom1"] =
{
  label = "Doom"

  priority = 98  -- keep at second spot

  format = "doom"

  tables =
  {
    DOOM, DOOM1
  }

  hooks =
  {
    setup        = DOOM1.setup
    get_levels   = DOOM1.get_levels
    end_level    = DOOM1.end_level
    all_done     = DOOM1.all_done
  }
}


UNFINISHED["ultdoom"] =
{
  label = "Ultimate Doom"

  extends = "doom1"

  priority = 97  -- keep at third spot
  
  -- no additional tables

  -- no additional hooks
}


OB_GAMES["tnt"] =
{
  label = "TNT Evilution"

  extends = "doom2"

  tables =
  {
    TNT
  }
}


OB_GAMES["plutonia"] =
{
  label = "Plutonia Exp."

  extends = "doom2"

  tables =
  {
    PLUTONIA
  }
}


OB_GAMES["freedoom"] =
{
  label = "FreeDoom 0.7"

  extends = "doom2"

  tables =
  {
    FREEDOOM
  }
}

