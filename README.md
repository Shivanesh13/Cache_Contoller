# Cache_Contoller

# Cache Controller Design Description

## Overview
The second design implements a highly configurable cache controller using SystemVerilog. It features a 4-way set associative cache by default, but can be parameterized for different configurations. The design follows a modular approach with separate components for the tag array, data array, and replacement policy logic.

## Key Parameters
- `ADDR_WIDTH`: 32 bits (CPU address width)
- `DATA_WIDTH`: 32 bits (CPU data width)
- `LINE_SIZE`: 64 bytes (Cache line size)
- `NUM_SETS`: 64 (Number of cache sets)
- `ASSOCIATIVITY`: 4 (Ways per set)
- `CACHE_SIZE`: 16,384 bytes (Total cache capacity)

## Architectural Components

### 1. Cache Controller Module
The top-level module manages the FSM and coordinates between CPU, memory, and cache components. It decodes addresses into tag, index, and offset components and maintains the cache state.

### 2. Tag Array
Stores and manages the tag information for each cache line, including:
- Tag bits
- Valid bit
- Dirty bit
The module handles tag comparisons for hit detection and way selection.

### 3. Data Array
Stores the actual cached data and supports:
- Single word reads/writes (for CPU operations)
- Full line reads/writes (for memory transfers)

### 4. Tree-Based LRU
Implements a replacement policy using a tree-based Least Recently Used algorithm:
- Maintains replacement state for each set
- Handles hit updates to track usage
- Provides replacement way selection on cache misses

## State Machine
The controller operates using a 6-state FSM:
1. `IDLE`: Waits for CPU requests
2. `TAG_CHECK`: Checks if address hits in cache
3. `MEM_UPDATE`: Handles cache hits for reads/writes
4. `WRITEBACK`: Writes dirty cache lines to memory
5. `FETCH`: Retrieves new cache lines from memory
6. `CACHE_READ`: Completes read operation after fetch

## Interface Signals

### CPU Interface
- Address, data, and control signals for CPU read/write operations
- CPU ready signal for handshaking

### Memory Interface
- Address, data, and control signals for memory operations
- Memory ready signal for handshaking

## Key Design Features

1. **Parameterized Configuration**: All key dimensions can be adjusted via parameters
2. **Modular Design**: Separate modules with clear interfaces
3. **Full FSM Control**: Well-defined state transitions for all cache operations
4. **Scalable Replacement**: Tree-based LRU implementation that scales with associativity
5. **Clean Timing**: State machine design with clear clock boundaries

## Performance Considerations
- Write-back policy to reduce memory traffic
- Set associativity to reduce conflict misses
- LRU replacement to optimize cache utilization
- Full cache line transfers for memory efficiency

This design represents a modern cache controller architecture suitable for processors requiring good memory performance with configurable cache parameters to meet system requirements.
