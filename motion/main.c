#include "USBMicroX.h"
#include <fcntl.h>

#define OUT_FILE "MOTION"
#define SERIAL "101128160542"
#define SLEEP_DELAY 250000
#define TIMEOUT 2

// Prototypes
void timeout(int sig);

int main(int argc, const char * argv[])
{
	int fd;
	unsigned char data;
	
	// Grab a USBmicroX context
	USBmX_ContextRef ctx = USBmX_Create();
	USBmX_Begin(ctx);
	
	// Find the specified device
	USBmX_DeviceRef device = USBmX_DeviceWithSerial(ctx, SERIAL);
	if (!device) {
		fprintf(stderr, "Device not found: %s\n", SERIAL);
		exit(1);
	}
	
	// Monitor for USB timeouts
	signal(SIGALRM, timeout);

	// Read forever
	while (1) {
		// Read from the device
		alarm(TIMEOUT);
		if (USBmX_ReadA(device, &data) != 0) {
			fprintf(stderr, "Device read error\n");
			exit(1);
		}
		alarm(0);
		
		// Pin A5 is high when we've got motion
		if (data & 0x20) {
			printf("Motion detected");
			if (utimes(OUT_FILE, NULL) != 0) {
				fprintf(stderr, "Creating outfile\n");
				if (errno == ENOENT) {
					fd = open(OUT_FILE, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH);
					if (fd <= 0 || close(fd) != 0) {
						fprintf(stderr, "Error creating output file (%d): %s\n", errno, OUT_FILE);
						exit(1);
					}
				} else {
					fprintf(stderr, "Error touching output file (%d): %s\n", errno, OUT_FILE);
				}
			}
		}
		printf("\n");
		
		// Sleep and loop
		usleep(SLEEP_DELAY);
	}
	
	// Cleanup
	USBmX_Destroy(ctx);
    return 0;
}

// Catch the timeout
void timeout(int sig) {
	signal(sig, SIG_IGN);
	fprintf(stderr, "Timeout waiting for USB read\n");
	exit(1);
}