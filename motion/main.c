#include "USBMicroX.h"
#include <fcntl.h>
#include <sys/stat.h>

#define DATA_DIR "plexMonitor/"
#define OUT_FILE "MOTION"
#define SERIAL "101128160542"
#define SLEEP_DELAY 250000
#define TIMEOUT 2

//#define DEBUG

// Prototypes
void timeout(int sig);
USBmX_DeviceRef init();
unsigned char readDev(USBmX_DeviceRef dev);

// Globals
USBmX_ContextRef ctx;

int main(int argc, const char * argv[])
{
	USBmX_DeviceRef device;
	int fd;
	size_t len;
	char *datadir, *outfile;
	struct stat statbuf;

	// Construct the data directory and output file paths
	len = confstr(_CS_DARWIN_USER_TEMP_DIR, NULL, (size_t) 0);
	len += sizeof(DATA_DIR);
	datadir = malloc(len);
	outfile = malloc(len + sizeof(OUT_FILE));
	if (datadir == NULL || outfile == NULL) {
		fprintf(stderr, "Out of memory\n");
		exit(1);
	}
	confstr(_CS_DARWIN_USER_TEMP_DIR, datadir, len);
	strlcat(datadir, DATA_DIR, len);
	strlcpy(outfile, datadir, len);
	strlcat(outfile, OUT_FILE, len + sizeof(OUT_FILE));

	// Create the datadir as needed
	stat(datadir, &statbuf);
	if (!S_ISDIR(statbuf.st_mode)) {
		fprintf(stderr, "Creating data directory: %s\n", datadir);
		if (mkdir(datadir, S_IRUSR | S_IWUSR | S_IXUSR) != 0) {
			fprintf(stderr, "Error creating data directory (%s): %s\n", strerror(errno), outfile);
			exit(1);
		}
	}

	// Create the output file as needed
	stat(outfile, &statbuf);
	if(!S_ISREG(statbuf.st_mode)) {
		fprintf(stderr, "Creating output file: %s\n", outfile);
		fd = open(outfile, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
		if (fd <= 0 || close(fd) != 0) {
			fprintf(stderr, "Error creating output file (%s): %s\n", strerror(errno), outfile);
			exit(1);
		}
	}

	// Monitor for alarms
	signal(SIGALRM, timeout);

	// Setup the USB device
	device = init(SERIAL);
	
	// Read forever
	while (1) {
		// If we detected motion
		if (readDev(device)) {
			#ifdef DEBUG
			printf("Motion detected\n");
			#endif
			if (utimes(outfile, NULL) != 0) {
				if (errno == ENOENT) {
				} else {
					fprintf(stderr, "Error touching output file (%s): %s\n", strerror(errno), outfile);
				}
			}
		} else {
			#ifdef DEBUG
			printf("\n");
			#endif
		}	

		// Delay and loop
		usleep(SLEEP_DELAY);
	}
	
	// Cleanup (we never get here)
	USBmX_Destroy(ctx);
	return 0;
}

// Catch the timeout
void timeout(int sig) {
	signal(sig, SIG_IGN);
	fprintf(stderr, "Timeout waiting for USB read\n");
	exit(1);
}

// Setup the USBMicro context and build refs to our specified devices
USBmX_DeviceRef init(const char *serial) {
	USBmX_DeviceRef device;

	// Create a new USBmicroX context as needed
	if (!ctx) {
		ctx = USBmX_Create();
		USBmX_Begin(ctx);
	}

	// Find the specified device
	device = USBmX_DeviceWithSerial(ctx, serial);
	if (!device) {
		fprintf(stderr, "Device not found: %s\n", serial);
		exit(1);
	}

	// Return device handles
	return device;
}

// Read the specified USBMicro device
unsigned char readDev(USBmX_DeviceRef dev) {
	unsigned char data = 0x00;

	// Enable the timeout
	alarm(TIMEOUT);

	// Read from the device
	if (USBmX_ReadA(dev, &data) != 0) {
		fprintf(stderr, "Device read error\n");
		exit(1);
	}

	// Clear the timeout
	alarm(0);

	// Return pin A5
	return (data & 0x20);
}
