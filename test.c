
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <netdb.h>

#include <string.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdio.h>

struct linux_dirent64 {
    ino_t          d_ino;    /* 64-bit inode number */
    off_t          d_off;    /* 64-bit offset to next structure */
    unsigned short d_reclen; /* Size of this dirent */
    unsigned char  d_type;   /* File type */
    char           d_name[]; /* Filename (null-terminated) */
};

void dump_sym(const char *sym, const void *bytes, size_t len)
{
	printf("%s: db 0x%02X", sym, ((unsigned char *) bytes)[0]);
	for(size_t i = 1; i < len; ++i)
		printf(", 0x%02X", ((unsigned char *) bytes)[i]);
	printf("\n%s_len equ %zu\n", sym, len);
}

void dump_getaddr_NULL()
{
	struct addrinfo *myaddr, hints;
	int rv;

	memset(&hints, 0, sizeof hints);
	hints.ai_family = AF_INET;
	hints.ai_socktype = SOCK_STREAM;

	if((rv = getaddrinfo(NULL, "00", &hints, &myaddr)) != 0) {
			fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(rv));
			exit(1);
	}

	printf("getaddrinfo():");
	dump_sym("addr", myaddr->ai_addr, myaddr->ai_addrlen);
	freeaddrinfo(myaddr);
}

void dump_sockaddr_storage_len()
{
	printf("sizeof(struct sockaddr_storage) = 0x%02lX\n", sizeof(struct sockaddr_storage));
}

void dump_port_offset()
{
	struct sockaddr_in in;
	printf("(struct sockaddr_in (size=0x%02lX)) in.sin_port (size=0x%02lX): 0x%02lX\n",
		sizeof(struct sockaddr_in), sizeof(in.sin_port),
		((void*)&in.sin_port) - ((void*)&in));
}

void dump_st_offsets()
{
	struct stat st;
	printf("(struct stat (size=0x%02lX))\n\tst.st_size (size=0x%02lX): 0x%02lX\n\tst.st_mode (size=0x%02lX): 0x%02lX\n",
		sizeof(struct stat),
		sizeof(st.st_size), ((void*)&st.st_size) - ((void*)&st),
		sizeof(st.st_mode), ((void*)&st.st_mode) - ((void*)&st));
}

void dump_S_IFDIR()
{
	printf("S_IFDIR equ 0x%04X\n", S_IFDIR);
}

void test_stat_S_IFDIR()
{
	struct stat st;
	stat(".", &st);
	printf("stat(\".\"); st.st_mode: 0x%04X (& S_IFDIR=0x%04X)\n", st.st_mode, st.st_mode & S_IFDIR);
}

void dump_linux_dirent64()
{
    struct linux_dirent64 s;
    printf("d_ino@%zu(size=%zu) d_off@%zu(size=%zu) d_reclen@%zu(size=%zu) d_type@%zu(size=%zu) d_name@%zu(size=variable)\n",
        (void *) &s.d_ino - (void *) &s, sizeof(s.d_ino),
        (void *) &s.d_off - (void *) &s, sizeof(s.d_off),
        (void *) &s.d_reclen - (void *) &s, sizeof(s.d_reclen),
        (void *) &s.d_type - (void *) &s, sizeof(s.d_type),
        (void *) &s.d_name - (void *) &s);
}

int main()
{
	dump_getaddr_NULL();
	dump_sockaddr_storage_len();
	dump_port_offset();
	dump_st_offsets();
	dump_S_IFDIR();
	test_stat_S_IFDIR();
	dump_linux_dirent64();
	return 0;
}

