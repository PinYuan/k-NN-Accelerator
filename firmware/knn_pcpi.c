#include "firmware.h"
#define K						5
#define MAX_INT                 2147483647
#define DATA_LENGTH             3073
#define NUM_CLASS				10
#define NUM_TEST_IMAGE			50
#define NUM_TRAIN_IMAGE			950
#define IMAGE_OFFSET 			0x00010000

int soft_L2(int test, int train);
int soft_vote(unsigned int distances[NUM_TRAIN_IMAGE]);

void knn_pcpi(void)
{
	unsigned int distances[NUM_TRAIN_IMAGE];
	int right = 0;
	int soft_label = 0, hard_label = 0;
	int start, end, software_ticks, hardware_ticks;

	for(int test_image_index = 0; test_image_index < NUM_TEST_IMAGE; test_image_index++){
		//just an example of single test image!
	    for(int train_image_index = 0; train_image_index < NUM_TRAIN_IMAGE ;train_image_index++){
			//TODO: implement hardware & software versions of pairwise distance computation
			// argu1 means which test image
			// argu2 means which train image

			distances[train_image_index] = hard_knn_pcpi(test_image_index, train_image_index + NUM_TEST_IMAGE);
		/*	print_str("\nhard : distances[");
			print_dec(i);
			print_str("] = ");	
			print_dec(distances[i]);
		*/		
			// software version(very slow)
			//if(test_image_index == 11)distances[train_image_index] = soft_L2(test_image_index, train_image_index + NUM_TEST_IMAGE);
		/*	print_str("\nsoft : distances[");
			print_dec(i);
			print_str("] = ");	
			print_dec(dist);
		*/	
		}
		
		
		//TODO: implement hardware version of label voting
		//you can use the algorithm we provided below, or any better algorithm you can think of
		
		start = tick();
		soft_label = soft_vote(distances);
		end = tick();
		software_ticks += end - start;

		start = tick();
		hard_label = hard_knn_pcpi(0, 0);
		end = tick();
		hardware_ticks += end - start;
		
		int rightLabel = *(volatile uint32_t*)(IMAGE_OFFSET + (test_image_index) * DATA_LENGTH * 4);
		
		if(rightLabel == hard_label) right++;


		print_str("\nThe result of test image soft_vote_knn [ ");
		print_dec(test_image_index);
		print_str(" ]: ");
		print_dec(soft_label);
		print_str("\n");

		print_str("\nThe result of test image hard_vote_knn [ ");
		print_dec(test_image_index);
		print_str(" ]: ");
		print_dec(hard_label);
		print_str("\n");

		print_str("\nThe answer of test image [ ");
		print_dec(test_image_index);
		print_str(" ]: ");
		print_dec(rightLabel);
		print_str("\n");

		print_str("----------------------------------------");
	}

	print_str("\nTotal software_vote_tick: ");
	print_dec(software_ticks);
	print_str("\n");

	print_str("\nTotal hardware_vote_tick: ");
	print_dec(hardware_ticks);
	print_str("\n");

	// compute accuracy
	print_str("\nKNN(K: ");
	print_dec(K);
	print_str(")");
	print_str("  accuracy: ");
	print_dec(right / 50.0 * 100 );
	print_str("%\n");
}

int soft_L2(int test, int train){
	// For each image, first byte is label, and following 1024 bytes are red channels...
	// (label, red, green, blue)
	int dist = 0;
	int red_diff, green_diff, blue_diff;
	int red_test, red_train, green_test, green_train, blue_test, blue_train;
	for(int i=0; i<1024; i++){
		red_test = *(volatile uint32_t*)(IMAGE_OFFSET + (test * DATA_LENGTH + i + 1) * 4);
		red_train = *(volatile uint32_t*)(IMAGE_OFFSET + (train * DATA_LENGTH + i + 1) * 4);
		green_test = *(volatile uint32_t*)(IMAGE_OFFSET + (test * DATA_LENGTH + i + 1025) * 4);
		green_train = *(volatile uint32_t*)(IMAGE_OFFSET + (train * DATA_LENGTH + i + 1025) * 4);
		blue_test = *(volatile uint32_t*)(IMAGE_OFFSET + (test * DATA_LENGTH + i + 2049) * 4);
		blue_train = *(volatile uint32_t*)(IMAGE_OFFSET + (train * DATA_LENGTH + i + 2049) * 4);

		red_diff = (red_test > red_train)?(red_test-red_train):(red_train-red_test);
		green_diff = (green_test > green_train)?(green_test-green_train):(green_train-green_test);
		blue_diff = (blue_test > blue_train)?(blue_test-blue_train):(blue_train-blue_test);

		dist = dist + red_diff*red_diff + green_diff*green_diff + blue_diff*blue_diff; 
	}
	return dist;	 
}

int soft_vote(unsigned int distances[NUM_TRAIN_IMAGE]){
	int i, j;

	unsigned int top_images[K][2];
	for(i = 0; i < K; i++){
		top_images[i][0] = MAX_INT; //distances of top-K closest images
		top_images[i][1] = 0;		//labels of top-K closest images
	}
		
	//iterate through all images, only keep the top-K closest images
	for(i = 0; i < NUM_TRAIN_IMAGE; i++){
        int insert_idx = -1;
		//get the index to insert, so that distances after this index are all larger
		for(j = 0; j < K; j++){
			if(distances[i] < top_images[j][0]){
				insert_idx = j;
				break;
			}
		}
		if(insert_idx >= 0){
			//insert new data, shift the rest
			for(j = K - 1; j > insert_idx; j--){
				top_images[j][0] = top_images[j-1][0];
				top_images[j][1] = top_images[j-1][1];
			}
			top_images[insert_idx][0] = distances[i];
			top_images[insert_idx][1] = i;
		}
	}

	int max_count = 0;
	int max_label = 0;
	int num_labels[NUM_CLASS] = {0};

	//find the label which gets the most votes
	for(i = 0; i < K; i++){
		int label = *(volatile uint32_t*)(IMAGE_OFFSET + (top_images[i][1] + NUM_TEST_IMAGE) * DATA_LENGTH * 4);
		num_labels[label]++;
		if(num_labels[label] > max_count){
			max_count = num_labels[label];
			max_label = label;
		}else if(num_labels[label] == max_count && label < max_label){
			max_count = num_labels[label];
			max_label = label;
		}
	}

	// DEBUG
	for(int a=0; a<K; a++){
		print_str("\nsoft:");
		print_dec(top_images[a][0]);
		print_str(" ");
	}
	print_str("\n");
	return max_label;
}