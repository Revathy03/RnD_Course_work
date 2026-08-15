# GPU Parameters
# If CUDA is installed in a different location, you can override these paths:
# make CUDA_PATH=/usr/local/cuda-12.4
CUDA_PATH ?= /usr/local/cuda
GDS_PATH ?= $(CUDA_PATH)

# CUDA Compiler (Required for kernels)
NVCC = nvcc
NVCC_FLAGS = -std=c++17 -I./include -I$(CUDA_PATH)/include -arch=sm_70 

# Linking
LDFLAGS = -L$(CUDA_PATH)/lib64 -lcudart -lcufile

TARGETS = gds_example main_toy_example

all: $(TARGETS)

gds_example: src/gds_example.cu include/ObjectStore.hpp include/CudaSerialization.hpp
	$(NVCC) $(NVCC_FLAGS) src/gds_example.cu -o gds_example $(LDFLAGS)

main_toy_example: src/main_toy_example.cu include/ObjectStore.hpp include/CudaSerialization.hpp
	$(NVCC) $(NVCC_FLAGS) src/main_toy_example.cu -o main_toy_example $(LDFLAGS)

run: all
	./gds_example
	./main_toy_example

clean:
	rm -f $(TARGETS)
	rm -rf data/

.PHONY: all run clean
