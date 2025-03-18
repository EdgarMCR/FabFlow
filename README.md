# **FabFlow**
A* pathfinding library for the Odin programming language

## **✨ Features**
✔️ A* Pathfinding Algorithm – Find the shortest path efficiently.  
✔️ Multiple Heuristics – Choose from Euclidean (default), Manhattan, Octile, and Chebyshev.  
✔️ Configurable Costs & Obstacles – Set custom movement costs and blocked tiles.    
✔️ Multiple Diagonal Modes – Choose from NO_CORNER_CUT (default), NEVER, and ALWAYS.

## **Setup**
To include FabFlow in your **Odin** project, add it as a Git submodule:

```sh
git submodule add https://github.com/tykim83/FabFlow.git vendor/FabFlow
git submodule update --init --recursive
```

## **Quick Start**
```sh
package fabflowtest

import "core:fmt"
import ff "/vendor/FabFlow"

main :: proc() {  
    blocked_tiles: [][2]i32 = {
        {4, 2}, {4, 3}, {4, 4}, // Vertical block
        {1, 4}, {2, 4}, {3, 4}, // Horizontal block
    }

    // Initialize 8x8 grid
    grid := ff.init_grid({0,0}, {8, 8})
    defer ff.destroy_grid(&grid)

    // Set blocked tiles
    for tile in blocked_tiles {
        ff.set_blocked_tile(&grid, tile)
    }

    // Set custom movement cost
    ff.set_tile_cost(&grid, {4, 1}, 3.0)

    // Find path from (0,0) to (7,7)
    path, found := ff.find_path(grid, {0, 0}, {7, 7})
    defer ff.destroy_path(&path)

    if found {
        fmt.println("Path found:")
        for node, i in path.nodes {
            fmt.printf("%v ->(%v, %v) ", i, node.tile.pos.x, node.tile.pos.y)
        }
    } else {
        fmt.println("No path found.")
    }
}
```

## **Credits & Inspiration**
FabFlow was inspired by [odin_pathgrid](https://github.com/scoobery/odin_pathgrid) by **scoobery**. 
