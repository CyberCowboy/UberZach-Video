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

int main(int argc, const char * argv[])
{
	int fd;
	size_t len;
	char *outfile, *datadir;
	struct stat statbuf;
	unsigned char data;

	// Construct the output file path
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

	// Create the datadir and outfile as needed
	stat(datadir, &statbuf);
	if (!S_ISDIR(statbuf.st_mode)) {
		fprintf(stderr, "Creating data directory: %s\n", datadir);
		if (mkdir(datadir, S_IRUSR | S_IWUSR | S_IXUSR) != 0) {
			fprintf(stderr, "Error creating data directory (%s): %s\n", strerror(errno), outfile);
			exit(1);
		}
	}
	stat(outfile, &statbuf);
	if(!S_ISREG(statbuf.st_mode)) {
		fprintf(stderr, "Creating output file: %s\n", outfile);
		fd = open(outfile, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
		if (fd <= 0 || close(fd) != 0) {
			fprintf(stderr, "Error creating output file (%s): %s\n", strerror(errno), outfile);
			exit(1);
		}
	}

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
