package fabflow

import "core:math"
import "core:slice"
import "core:mem"
import vmem "core:mem/virtual"
import pq "core:container/priority_queue"

Vector2 :: [2]i32

SMALL_TILE_SIZE : Vector2 : {1, 1}

Grid :: struct {
    region: struct { min, max: Vector2 },
    cols: i32,
    rows: i32,
    tiles : []GridTile,
    compute_heuristic: proc(a, b: ^AStar_Node) -> f32,
    diagonal_mode: AStar_Diagonal_Mode,
    allocator : mem.Allocator
}

Path :: struct {
    nodes: []^AStar_Node,
    arena: vmem.Arena,
}

AStar_Node :: struct {
    tile   : ^GridTile,
    fCost  : f32, 
    gCost  : f32,  
    hCost  : f32,
    parent : ^AStar_Node,
}

GridTile :: struct {
    pos       : [2]f32,
    isWalkable: bool,
    moveCost  : f32,
}

AStar_Diagonal_Mode :: enum {
    NEVER, // Manhattan works best in non-diagonal grids 
    NO_CORNER_CUT, 
    ALWAYS,
}

heuristic_euclidean :: proc(a, b: ^AStar_Node) -> f32 {
    dx := math.abs(a.tile.pos.x - b.tile.pos.x)
    dy := math.abs(a.tile.pos.y - b.tile.pos.y)
    return math.sqrt(dx * dx + dy * dy) * 10
}

heuristic_manhattan :: proc(a, b: ^AStar_Node) -> f32 {
    dx := math.abs(a.tile.pos.x - b.tile.pos.x)
    dy := math.abs(a.tile.pos.y - b.tile.pos.y)
    return (dx + dy) * 10
}

heuristic_octile :: proc(a, b: ^AStar_Node) -> f32 {
    dx := math.abs(a.tile.pos.x - b.tile.pos.x)
    dy := math.abs(a.tile.pos.y - b.tile.pos.y)
    F :: math.SQRT_TWO - 1.0
    return dx < dy ? (F * dx + dy) * 10 : (F * dy + dx) * 10
}

heuristic_chebyshev :: proc(a, b: ^AStar_Node) -> f32 {
    dx := math.abs(a.tile.pos.x - b.tile.pos.x)
    dy := math.abs(a.tile.pos.y - b.tile.pos.y)
    return math.max(dx, dy) * 10
}

init_grid :: proc(region_min, region_max: Vector2, heuristic := heuristic_euclidean, diagonal := AStar_Diagonal_Mode.NO_CORNER_CUT, allocator := context.allocator, loc := #caller_location) -> Grid {
    area := region_max - region_min
    cols := area.x
    rows := area.y
    grid_tiles := make([]GridTile, cols * rows, allocator, loc)

    for row in 0..<rows {
        for col in 0..<cols {
            grid_tiles[row * cols + col] = GridTile {
                pos = { f32(col), f32(row) },
                isWalkable = true,
                moveCost  = 1.0,
            }
        }
    }
    return Grid {
        region = { region_min, region_max },
        tiles = grid_tiles,
        cols = cols,
        rows = rows,
        compute_heuristic = heuristic,
        diagonal_mode = diagonal,
        allocator = allocator
    }
}

destroy_grid :: proc(grid: ^Grid, loc := #caller_location) {
    if grid == nil { return }
    delete(grid.tiles, grid.allocator, loc)
}

set_blocked_tile :: proc(grid: ^Grid, pos: Vector2) {
    grid.tiles[to_index(pos, grid.cols)].isWalkable = false;
}

set_tile_cost :: proc(grid: ^Grid, pos: Vector2, cost: f32) {
    grid.tiles[to_index(pos, grid.cols)].moveCost = cost;
}

// Debug
when ODIN_DEBUG {
    openSetHistory: [dynamic][]^AStar_Node
    closedSetHistory: [dynamic][]^AStar_Node
}

find_path :: proc(grid: Grid, startCoord, targetCoord : Vector2, size := SMALL_TILE_SIZE, loc := #caller_location) -> (Path, bool) {
    cols := grid.cols
    rows := grid.rows
    found:= false

    path_arena: vmem.Arena
    path_arena_allocator := vmem.arena_allocator(&path_arena)

    neighbour_arena: vmem.Arena
    neighbour_arena_allocator := vmem.arena_allocator(&neighbour_arena)

    fail_path :: proc() -> (Path, bool) {
        return Path {}, false
    }
    
    // Validate coordinates.
    if !is_valid_footprint(grid, startCoord, size) || !is_valid_footprint(grid, targetCoord, SMALL_TILE_SIZE) {
        return fail_path()
    }

    // Create temporary AStar_Node storage
    astar_nodes := make([]AStar_Node, cols * rows, path_arena_allocator, loc)

    // Initialize each AStar_Node for its corresponding GridTile
    for &tile, i in grid.tiles {
        astar_nodes[i] = AStar_Node {
            tile  = &tile,
            fCost = math.max(f32),
            gCost = math.max(f32),
            hCost = 0,
            parent = nil,
        }
    }

    start := &astar_nodes[to_index(startCoord, cols)]

    valid_target : Vector2 = find_nearest_valid_target(grid, targetCoord, size);
    target := &astar_nodes[to_index(valid_target, cols)];

    if !target.tile.isWalkable {
        return fail_path()
    }

    start.gCost = 0
    start.hCost = grid.compute_heuristic(start, target)
    start.fCost = start.gCost + start.hCost
    
    // Initialize the open and closed sets.
    openSet: pq.Priority_Queue(^AStar_Node)
    pq.init(&openSet, astar_node_compare, pq.default_swap_proc(^AStar_Node), allocator = path_arena_allocator)
    pq.push(&openSet, start) // Push the starting node

    closedSet := make([dynamic]^AStar_Node, 0, path_arena_allocator, loc)

    // Debug
    when ODIN_DEBUG {
        openSetHistory = make([dynamic][]^AStar_Node, 0, path_arena_allocator, loc) 
        closedSetHistory = make([dynamic][]^AStar_Node, 0, path_arena_allocator, loc)
    }

    // A* search loop.
    for pq.len(openSet) > 0 {
        vmem.arena_destroy(&neighbour_arena, loc)

        current := pq.pop(&openSet)
        append(&closedSet, current)
        
        // Debug
        when ODIN_DEBUG {
            append(&openSetHistory, slice.clone(openSet.queue[:], path_arena_allocator, loc))
            append(&closedSetHistory, slice.clone(closedSet[:], path_arena_allocator, loc))
        }

        // If we reached the target, retrace and return the path.
        if current.tile == target.tile {
            found = true
            break
        }
        
        // Process each neighbour.
        neighbours := get_neighbours(grid, size, current, astar_nodes, neighbour_arena_allocator)
        for &neighbour in neighbours {
            if !neighbour.tile.isWalkable {
                continue
            }
            // If neighbour is in closedSet, skip it.
            if is_node_in_closed_set(closedSet[:], neighbour) {
                continue
            }
            
            newCost := current.gCost + movement_cost(current, neighbour)

            // Check if we should update this node
            if newCost < neighbour.gCost {
                neighbour.gCost = newCost
                neighbour.hCost = grid.compute_heuristic(neighbour, target)
                neighbour.fCost = neighbour.gCost + neighbour.hCost
                neighbour.parent = current

                // If it's not already in openSet, push it
                pq.push(&openSet, neighbour) 
            }
        }
    }

    if !found {
        return fail_path()
    }

    path := retrace_path(start, target, path_arena_allocator)
    return Path {
        nodes = path,
        arena = path_arena,
    }, true
}

destroy_path :: proc (path: ^Path, loc := #caller_location) {
    if path == nil || len(path.nodes) == 0 {
        return 
    }

    vmem.arena_destroy(&path.arena, loc)
}

@(private = "file")
retrace_path :: proc(start, target: ^AStar_Node, allocator := context.allocator, loc := #caller_location) -> []^AStar_Node { 
    path := make([dynamic]^AStar_Node, allocator, loc) 
    current := target

    for current.tile.pos != start.tile.pos {
        append(&path, current)
        current = current.parent
    }
    append(&path, start) 

    slice.reverse(path[:])
    return path[:]
}

@(private = "file")
get_neighbours :: proc(grid: Grid, size: Vector2, node: ^AStar_Node, nodes: []AStar_Node, allocator := context.allocator, loc := #caller_location) -> []^AStar_Node {
    neighbours := make([dynamic]^AStar_Node, 0, allocator, loc)

    pos : Vector2 = { i32(node.tile.pos.x), i32(node.tile.pos.y) }
    cols  := grid.cols
    rows  := grid.rows

    for dx in -1..=1 {
        for dy in -1..=1 {
            if dx == 0 && dy == 0 {
                continue
            }

            new_pos : Vector2 = { pos.x + i32(dx), pos.y + i32(dy) }

            if !is_valid_footprint(grid, new_pos, size) {
                continue
            }

            index := new_pos.y * cols + new_pos.x
            neighbor := &nodes[index]

            if dx != 0 && dy != 0 {

                if grid.diagonal_mode == AStar_Diagonal_Mode.NEVER {
                    continue 
                }

                if grid.diagonal_mode == AStar_Diagonal_Mode.NO_CORNER_CUT {
                    if !is_valid_footprint(grid, {pos.x + i32(dx), pos.y}, size) ||
                       !is_valid_footprint(grid, {pos.x, pos.y + i32(dy)}, size) {
                        continue
                    }
                }
            }

            append(&neighbours, neighbor)
        }
    }
    return neighbours[:]
}

@(private = "file")
find_nearest_valid_target :: proc(grid: Grid, target: Vector2, size: Vector2) -> Vector2 {
    if is_valid_footprint(grid, target, size) {
        return target;
    }

    radius := 1;
    for {
        for dx in -radius..=radius {
            for dy in -radius..=radius {
                candidate : Vector2 = { target.x + i32(dx), target.y + i32(dy) };
                if math.abs(dx) != radius && math.abs(dy) != radius {
                    continue;
                }
                if is_valid_footprint(grid, candidate, size) {
                    return candidate;
                }
            }
        }
        radius += 1;

        if radius > 10 { break; }
    }

    return target;
}

@(private = "file")
to_index :: proc(pos: Vector2, cols: i32) -> i32 {
    return pos.y * cols + pos.x
}

@(private = "file")
is_node_in_closed_set :: proc(closedSet: []^AStar_Node, node: ^AStar_Node) -> bool {
    for n in closedSet {
        if n == node {
            return true
        }
    }
    return false
}

@(private = "file")
is_valid_tile :: proc(grid: Grid, pos: Vector2) -> bool {
    return pos.x >= grid.region.min.x && pos.x < grid.region.max.x &&
           pos.y >= grid.region.min.y && pos.y < grid.region.max.y &&
           grid.tiles[to_index(pos, grid.cols)].isWalkable;
}

@(private = "file")
is_valid_footprint :: proc(grid: Grid, pos: Vector2, size: Vector2) -> bool {
    if size == SMALL_TILE_SIZE {
        return is_valid_tile(grid, pos);
    }

    for dx in 0 ..< size[0] {
        for dy in 0 ..< size[1] {
            current : Vector2 = { pos[0] + dx, pos[1] + dy };
            if !is_valid_tile(grid, current) {
                return false;
            }
        }
    }
    return true;
}

@(private = "file")
movement_cost :: proc(a, b: ^AStar_Node) -> f32 {
    dx := math.abs(a.tile.pos.x - b.tile.pos.x)
    dy := math.abs(a.tile.pos.y - b.tile.pos.y)
    base: f32 = 10.0
    if dx > 0 && dy > 0 {
        base = 14.0
    } 
    return base * b.tile.moveCost
}

@(private = "file")
astar_node_compare :: proc(a, b: ^AStar_Node) -> bool {
    return a.fCost < b.fCost
}
