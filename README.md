## About
This is just a little project against boredem.
This snake is completly written in assembly and will feature some stuff other assembly snakes don't e.g. unicode for background, snake and fruits. 

## Roadmap

- [x] program
- [x] alt-screen
- [x] background
- [ ] snake
- [ ] fruit spawning
- [ ] start screen
- [ ] Windows support
- [ ] MacOS support

## Install

### Quick Start
Download the snake file and make it executable with `chmod +x snake`.

### Build
Clone this repo or download the snake.asm file and build it using nasm:
´´´
nasm -f elf64 snake.asm -o snake.o
ld snake.o -o snake
´´´

## Notes
I'm not against using in coding, so I used ai to debug and find errors when I couldn't find them, but the code was completly self-written and is my first assembly project.
