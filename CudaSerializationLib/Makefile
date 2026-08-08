# GPU Parameters
# If CUDA is installed in a different location, you can override these paths:
# make CUDA_PATH=/usr/local/cuda-12.4
CUDA_PATH ?= /usr/local/cuda
GDS_PATH ?= $(CUDA_PATH)

# CUDA Compiler (Required for kernels)
NVCC = nvcc
NVCC_FLAGS = -std=c++17 -I. -I$(CUDA_PATH)/include -arch=sm_70 

# Linking
LDFLAGS = -L$(CUDA_PATH)/lib64 -lcudart -lcufile

TARGET = main
SRC = main.cu

all: $(TARGET)

$(TARGET): $(SRC) ObjectStore.hpp
	$(NVCC) $(NVCC_FLAGS) $(SRC) -o $(TARGET) $(LDFLAGS)

run: all
	./$(TARGET)

clean:
	rm -f $(TARGET)
	rm -rf data/

.PHONY: all run clean
