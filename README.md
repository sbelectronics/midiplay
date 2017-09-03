# Roland MPU-401 Intelligent Midi Player

Scott Baker (http://www.smbaker.com/)

## Intro

This is the start of my MPU-401 / MT-32 intelligent-mode player.

Status

- tested under DOSBOX (I don't have an MPU-401 yet)
- works in polling mode (-O)
- works in interrupt-drive mode (default)
- Does not support sysex
- Does not support conductor (no tempo changes, etc)
- Track 0 is ignored, and assumed to be all meta/sysex stuff
- Tracks 1-8 are mapped to 0-7
- Only supports 8 tracks, because that's all the MPU-401 supports

I suggest you confine yourself to reasonable, relatively small midi files. Those huge sierra soundtracks out there that are 600 KB or more are bound to just cause problems.

I tested this using some midi files from http://ftp.monash.edu.au/pub/midi.songs/MT-32/

- `buster.mid`: a very simple one-track ghostbusters theme song
- `afterdrk.mid`: a complex song with about a dozen tracks, note that it'll take about 30 seconds before you start to hear sound.

## Why intelligent mode?

Why not?

The MPU-401 features two different modes: UART mode and intelligent mode. UART mode simply sends characters out the midi port. The host computer is responsible for sequencing -- sending the right notes at the right time.

Intelligent mode, on the other hand, offloads the task of sequencing to the CPU in the MPU-401. The MPU-401 keeps a running track of time counters for each channel, and outputs the appopriate midi messages at the appropriate times. This frees up the host computer so it can do other tasks. This was especially important in older computers, and you will find many older games (Sierra adventure games, etc) use intelligent mode.

So why write an intelligent mode player? Well, first of all, I couldn't find an existing one -- maybe I didn't look hard enough, maybe there was one and it was lost to history, or maybe mine is the first. As to why I chose to do it, it's a matter of nostalgia. I wanted to play midi using the same mechanism that the early sierra games did.

## Limitations

The MPU-401 only supports 8 channels. Many midi files use more than 8 channels. You won't hear the sound from those other channels. Bummer.

## Using the program

Type `midiplay -h` for help, or `midiplay -p <filename.mid>` to play a file. There's numerous command-line options. Feel free to explore them.  