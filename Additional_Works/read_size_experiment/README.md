# GDS Performance Evaluation: I/O Size and Batching Impact Analysis

This experiment evaluates the impact of I/O size on GPUDirect Storage (GDS) throughput, with a focus on testing the limits of GDS Batching.

## Evaluation of the Batching Hypothesis

**Hypothesis**: GDS Batching increases throughput irrespective of the request size.

## Experiment Setup
- **IO Sizes**: 4KB, 1MB
- **File Sizes**: 1GB to 8GB
- **Configurations**: Batch Off vs. Batch On

## Results: Hypothesis Contradiction for Small I/O
The experiment results **contradicted** the hypothesis for small request sizes.

| IO Size | Mode | Avg Throughput | Result |
|---------|------|----------------|--------|
| **1MB** | Batch On | **~1.60 GiBps** | **Gain** (Supported) |
| **4KB** | Batch On | **~0.03 GiBps** | **Loss** (Contradicted) |

### Key Analysis
While batching is effective for large 1MB blocks, it resulted in a throughput **decrease** for 4KB blocks. This indicates that the management overhead associated with GDS Batching outweighs the benefits for small random I/O operations.
