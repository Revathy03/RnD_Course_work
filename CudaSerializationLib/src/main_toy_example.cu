#include <iostream>
#include <fstream>
#include <iomanip>
#include <vector>
#include <cmath>
#include <cuda_runtime.h>
#include "ObjectStore.hpp"

// Visualization Constants
const int IMG_SIZE = 512;

// Realistic ML Data Structure 1: Graph Node
struct GraphNode {
    int id;
    float x, y;          // 2D Plane Position (0.0 to 1.0)
    float features[16];   // ML Features

    template <class Archive>
    __device__ void serialize(Archive &ar) {
        ar(id, x, y);
        for (int i = 0; i < 16; ++i) ar(features[i]);
    }
};

// Realistic ML Data Structure 2: Graph Edge
struct GraphEdge {
    int source_id;
    int dest_id;
    float weight;

    template <class Archive>
    __device__ void serialize(Archive &ar) {
        ar(source_id, dest_id, weight);
    }
};

// --- RENDERING KERNELS ---

__global__ void clear_image(uint8_t *img) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x < IMG_SIZE && y < IMG_SIZE) {
        img[y * IMG_SIZE + x] = 0; // Black background
    }
}

__global__ void render_nodes(const GraphNode *nodes, int n, uint8_t *img) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        // Map 0.0-1.0 to pixel coordinates
        int px = (int)(nodes[i].x * (IMG_SIZE - 1));
        int py = (int)(nodes[i].y * (IMG_SIZE - 1));

        // Draw a 3x3 square for visibility
        for (int dy = -1; dy <= 1; ++dy) {
            for (int dx = -1; dx <= 1; ++dx) {
                int nx = px + dx;
                int ny = py + dy;
                if (nx >= 0 && nx < IMG_SIZE && ny >= 0 && ny < IMG_SIZE) {
                    img[ny * IMG_SIZE + nx] = 255; // White nodes
                }
            }
        }
    }
}

// Simple edge rendering (just endpoints for now to keep it clean)
__global__ void render_edges(const GraphNode *nodes, const GraphEdge *edges, int num_edges, uint8_t *img) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < num_edges) {
        int src = edges[i].source_id;
        int dst = edges[i].dest_id;
        
        // Sample points along the line segment
        float x1 = nodes[src].x, y1 = nodes[src].y;
        float x2 = nodes[dst].x, y2 = nodes[dst].y;
        
        for (float t = 0; t <= 1.0f; t += 0.05f) {
            int px = (int)((x1 + t * (x2 - x1)) * (IMG_SIZE - 1));
            int py = (int)((y1 + t * (y2 - y1)) * (IMG_SIZE - 1));
            if (px >= 0 && px < IMG_SIZE && py >= 0 && py < IMG_SIZE) {
                if (img[py * IMG_SIZE + px] == 0) 
                    img[py * IMG_SIZE + px] = 100; // Grey edges
            }
        }
    }
}

// --- UTILITIES ---

void save_ppm(const char *filename, uint8_t *d_img) {
    std::vector<uint8_t> h_img(IMG_SIZE * IMG_SIZE);
    cudaMemcpy(h_img.data(), d_img, IMG_SIZE * IMG_SIZE, cudaMemcpyDeviceToHost);

    std::ofstream ofs(filename, std::ios::binary);
    ofs << "P5\n" << IMG_SIZE << " " << IMG_SIZE << "\n255\n";
    ofs.write((char *)h_img.data(), h_img.size());
    ofs.close();
    std::cout << "[Visual] Saved " << filename << std::endl;
}

// --- INITIALIZATION KERNELS ---

__global__ void init_spatial_nodes(GraphNode *nodes, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        nodes[i].id = i;
        // Spiral pattern
        float angle = 0.1f * i;
        float r = 0.45f * (float)i / n;
        nodes[i].x = 0.5f + r * cosf(angle);
        nodes[i].y = 0.5f + r * sinf(angle);

        for (int j = 0; j < 16; ++j) {
            nodes[i].features[j] = __sinf(nodes[i].x * (j + 1));
        }
    }
}

__global__ void init_spatial_edges(GraphEdge *edges, int num_edges, int num_nodes) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < num_edges) {
        edges[i].source_id = i % num_nodes;
        edges[i].dest_id = (i + 5) % num_nodes;
        edges[i].weight = 1.0f;
    }
}

int main() {
    cudaFree(0);
    const int NUM_NODES = 2000;
    const int NUM_EDGES = 4000;
    const int threads = 256;

    std::cout << "--- [ML Graph & Image Simulation] ---" << std::endl;

    GraphNode *d_nodes;
    GraphEdge *d_edges;
    uint8_t *d_img;
    cudaMalloc(&d_nodes, NUM_NODES * sizeof(GraphNode));
    cudaMalloc(&d_edges, NUM_EDGES * sizeof(GraphEdge));
    cudaMalloc(&d_img, IMG_SIZE * IMG_SIZE);

    // 1. Initial State
    init_spatial_nodes<<<(NUM_NODES + threads - 1) / threads, threads>>>(d_nodes, NUM_NODES);
    init_spatial_edges<<<(NUM_EDGES + threads - 1) / threads, threads>>>(d_edges, NUM_EDGES, NUM_NODES);
    
    // Render Pre-Storage
    dim3 blockSize(16, 16);
    dim3 gridSize((IMG_SIZE + 15) / 16, (IMG_SIZE + 15) / 16);
    clear_image<<<gridSize, blockSize>>>(d_img);
    render_edges<<<(NUM_EDGES + threads - 1) / threads, threads>>>(d_nodes, d_edges, NUM_EDGES, d_img);
    render_nodes<<<(NUM_NODES + threads - 1) / threads, threads>>>(d_nodes, NUM_NODES, d_img);
    cudaDeviceSynchronize();
    save_ppm("graph_pre.ppm", d_img);

    // 2. Storage
    std::cout << "[Step 1] Storing to ObjectStore (GDS)..." << std::endl;
    ObjectStore::put(9001, d_nodes, NUM_NODES);
    ObjectStore::put(9002, d_edges, NUM_EDGES);

    // 3. Retrieval
    cudaMemset(d_nodes, 0, NUM_NODES * sizeof(GraphNode));
    cudaMemset(d_edges, 0, NUM_EDGES * sizeof(GraphEdge));
    
    std::cout << "[Step 2] Retrieving from ObjectStore..." << std::endl;
    ObjectStore::get(9001, d_nodes);
    ObjectStore::get(9002, d_edges);
    cudaDeviceSynchronize();

    // 4. Render Post-Retrieval
    clear_image<<<gridSize, blockSize>>>(d_img);
    render_edges<<<(NUM_EDGES + threads - 1) / threads, threads>>>(d_nodes, d_edges, NUM_EDGES, d_img);
    render_nodes<<<(NUM_NODES + threads - 1) / threads, threads>>>(d_nodes, NUM_NODES, d_img);
    cudaDeviceSynchronize();
    save_ppm("graph_post.ppm", d_img);

    std::cout << "\n--- Done. Compare 'graph_pre.ppm' and 'graph_post.ppm' to verify integrity. ---" << std::endl;

    cudaFree(d_nodes); cudaFree(d_edges); cudaFree(d_img);
    return 0;
}
