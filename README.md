# spongent-avr
Size-optimized Spongent hashing algorithm for ATtiny45

spongent.asm implements the Spongent hashing algorithm described by (Bogdanov et al., 2011) in constant time. It is optimized purely for size and is therefore too slow to be used in practice. The built-in "Spongent" input data hashes in a simulated 10 seconds. The implementation consists of 89 instructions, comprising 178 bytes. The sbox takes another 8 bytes. RAM usage is 54 bytes.

This project was done by Erik Schneider and myself as an assignment for the Kerckhoffs/Radboud University course Cryptographic Engineering.


Reference:

Bogdanov, Andrey, et al. "SPONGENT: A lightweight hash function." Cryptographic Hardware and Embedded Systems–CHES 2011. Springer Berlin Heidelberg, 2011. 312-325.
