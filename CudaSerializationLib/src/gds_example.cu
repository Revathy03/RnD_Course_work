#include <iostream>
#include <cuda_runtime.h>
#include "ObjectStore.hpp"

// User Structure A: Student Data
struct Student
{
    int id;
    int age;
    float gpa;
    char name[32];

    // User only needs to define how to serialize their struct
    template <class Archive>
    __device__ void serialize(Archive &ar)
    {
        ar(id, age, gpa, name);
    }
};

// User Structure B: Image Metadata + Pixels
struct Image
{
    int width;
    int height;
    float brightness;
    unsigned char data[64];

    template <class Archive>
    __device__ void serialize(Archive &ar)
    {
        ar(width, height, brightness);
        for(int i=0; i<64; ++i) ar(data[i]);
    }
};

// Kernel to initialize Student batch
__global__ void init_students(Student *s, int n)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n)
    {
        s[i].id = 5000 + i;
        s[i].age = 18 + (i % 10);
        s[i].gpa = 3.0f + (i * 0.01f);

        const char *name = "University_Student";
        for (int j = 0; name[j] != '\0' && j < 31; ++j)
            s[i].name[j] = name[j];
        s[i].name[31] = '\0';
    }
}

// Kernel to initialize Image batch
__global__ void init_images(Image *img, int n)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n)
    {
        img[i].width = 1920;
        img[i].height = 1080;
        img[i].brightness = 0.85f;
        for (int j = 0; j < 64; ++j)
            img[i].data[j] = (unsigned char)(j + i);
    }
}

int main()
{
    cudaFree(0); // Initialize CUDA context

    int num_records = 100;
    int threadsPerBlock = 256;
    int blocks = (num_records + threadsPerBlock - 1) / threadsPerBlock;

    // --- Step 1: Initialize User Data ---
    Student *devStudent;
    cudaMalloc(&devStudent, num_records * sizeof(Student));
    init_students<<<blocks, threadsPerBlock>>>(devStudent, num_records);

    Image *devImage;
    cudaMalloc(&devImage, num_records * sizeof(Image));
    init_images<<<blocks, threadsPerBlock>>>(devImage, num_records);
    cudaDeviceSynchronize();

    // --- Step 2: Transparent Storage (Serialization happens inside) ---
    std::cout << "[App] Storing Student Batch via ObjectStore library...\n";
    ObjectStore::put(1001, devStudent, num_records);

    std::cout << "[App] Storing Image Batch via ObjectStore library...\n";
    ObjectStore::put(2001, devImage, num_records);

    // --- Step 3: Retrieval & Print ---
    cudaMemset(devStudent, 0, num_records * sizeof(Student));
    cudaMemset(devImage, 0, num_records * sizeof(Image));

    std::cout << "\n[App] Retrieving data (Deserialization happens inside)...\n";
    ObjectStore::get(1001, devStudent);
    ObjectStore::get(2001, devImage);
    cudaDeviceSynchronize();

    // Copy first 5 records back to Host for printing
    Student hostStudents[5];
    Image hostImages[5];
    cudaMemcpy(hostStudents, devStudent, 5 * sizeof(Student), cudaMemcpyDeviceToHost);
    cudaMemcpy(hostImages, devImage, 5 * sizeof(Image), cudaMemcpyDeviceToHost);

    std::cout << "\n--- DATA VERIFICATION (Top 5 Records) ---\n";
    std::cout << "STUDENT A Data List:\n";
    for (int i = 0; i < 5; ++i)
    {
        std::cout << "  [" << i << "] ID: " << hostStudents[i].id
                  << " | Name: " << hostStudents[i].name
                  << " | GPA: " << hostStudents[i].gpa << "\n";
    }

    std::cout << "\nIMAGE B Data List:\n";
    for (int i = 0; i < 5; ++i)
    {
        std::cout << "  [" << i << "] Res: " << hostImages[i].width << "x" << hostImages[i].height
                  << " | Brightness: " << hostImages[i].brightness
                  << " | First Pixel: " << (int)hostImages[i].data[0] << "\n";
    }
    std::cout << "------------------------------------------\n";

    cudaFree(devStudent);
    cudaFree(devImage);
    return 0;
}
