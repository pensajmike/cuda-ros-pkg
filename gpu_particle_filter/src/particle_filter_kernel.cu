
// #include <gpu_particle_filter/gpu_particle_filter.h>
#include <gpu_particle_filter/particle_filter_kernel.h>

struct __align__(16) Points{
    float x;
    float y;

    __device__
        float magnitude(void) {
        return x * x + y *y;
    }
};

__global__
void hello(char *a, int *b) {
    a[threadIdx.x] += b[threadIdx.x];

}

void test_cuda(char* a, int* b) {

    char *ad;
    int *bd;
    const int csize = N*sizeof(char);
    const int isize = N*sizeof(int);

    printf("%s", a);

    cudaMalloc((void**)&ad, csize);
    cudaMalloc((void**)&bd, isize);
    cudaMemcpy(ad, a, csize, cudaMemcpyHostToDevice);
    cudaMemcpy(bd, b, isize, cudaMemcpyHostToDevice);

    dim3 dimBlock( blocksize, 1 );
    dim3 dimGrid( 1, 1 );
    hello<<<dimGrid, dimBlock>>>(ad, bd);
    cudaMemcpy(a, ad, csize, cudaMemcpyDeviceToHost);
    cudaFree(ad);
    cudaFree(bd);
}

template<typename T>
__device__ __forceinline__
T cuFloor(const T x) {
    return static_cast<T>(std::floor(x));
}


__global__
void boxFilterGPU(int *pixels, const int fsize) {
    int t_idx = threadIdx.x + blockIdx.x * blockDim.x;
    int t_idy = threadIdx.y + blockIdx.y * blockDim.y;
    int offset = t_idx + t_idy * blockDim.x * gridDim.x;

    int val = 0;
    int icounter = 0;
    if ((t_idx > fsize && t_idx < 640 - fsize) &&
        (t_idy > fsize && t_idy < 480 - fsize)) {
        for (int i = -fsize; i < fsize + 1; i++) {
            for (int j = -fsize; j < fsize + 1; j++) {
                int idx = (t_idx + j) + (t_idy + i) * blockDim.x * gridDim.x;
                val += pixels[idx];
                icounter++;
            }
        }
        pixels[offset] = val/icounter;
    }
}

void boxFilter(cv::Mat &image, const int size) {
    // cv::cvtColor(image, image, CV_BGR2GRAY);
    int lenght = static_cast<int>(image.rows * image.cols) * sizeof(int);
    int *pixels = (int*)malloc(lenght);

#ifdef _OPENMP
#pragma omp parallel for num_threads(8) collapse(2) shared(pixels)
#endif
    for (int i = 0; i < image.rows; i++) {
        for (int j = 0; j < image.cols; j++) {
            int index = j + (i * image.cols);
            pixels[index] = (int)image.at<uchar>(i, j);
        }
    }
    
    cudaEvent_t d_start;
    cudaEvent_t d_stop;
    cudaEventCreate(&d_start); 
    cudaEventCreate(&d_stop);
    cudaEventRecord(d_start, 0);
    
    int *d_pixels;
    cudaMalloc((void**)&d_pixels, lenght);
    cudaMemcpy(d_pixels, pixels, lenght, cudaMemcpyHostToDevice);
    
    dim3 dim_thread(blocksize, blocksize);
    dim3 dim_block(static_cast<int>(image.cols)/dim_thread.x,
                   static_cast<int>(image.rows)/dim_thread.y);

    int b_start = static_cast<int>((float)size/2.0f);

    std::cout << "val: " << b_start  << "\n";
    
    boxFilterGPU<<<dim_block, dim_thread>>>(d_pixels, b_start);

    int *download_pixels = (int*)malloc(lenght);
    cudaMemcpy(download_pixels, d_pixels, lenght, cudaMemcpyDeviceToHost);

    cudaEventRecord(d_stop, 0);
    cudaEventSynchronize(d_stop);
    float elapsed_time;
    cudaEventElapsedTime(&elapsed_time, d_start, d_stop);

    std::cout << "\033[33m ELAPSED TIME:  \033[0m" << elapsed_time/1000.0f
              << "\n";
    
    int stride = image.cols;
    int j = 0;
    int k = 0;
    for (int i = 0; i < image.cols * image.rows; i++) {
        if (i == stride) {
            j++;
            k = 0;
            stride += image.cols;
        }
        image.at<uchar>(j, k++) = download_pixels[i];
    }
    
    cudaFree(d_pixels);
    free(pixels);
    cudaEventDestroy(d_start);
    cudaEventDestroy(d_stop);
}
