#!/usr/bin/env python3
"""Original CC0 lo-fi loops. Requires numpy and ffmpeg only for authoring.
No recordings, downloaded samples, or third-party compositions are used.
"""
from pathlib import Path
import json
import subprocess
import tempfile
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/audio'
OUT.mkdir(parents=True, exist_ok=True)
RATE = 32000


def compose(name, title, bpm, chords, seed):
    rng = np.random.default_rng(seed)
    beat = 60 / bpm
    duration = beat * 64
    count = round(duration * RATE)
    mix = np.zeros((count, 2), dtype=np.float64)

    def place(start, sound, level=1, pan=0):
        indices = (np.arange(len(sound)) + round(start * RATE)) % count
        mix[indices, 0] += sound * level * (0.75 - pan * .25)
        mix[indices, 1] += sound * level * (0.75 + pan * .25)

    def note(midi, length, soft=False):
        t = np.arange(round(length * RATE)) / RATE
        f = 440 * 2 ** ((midi - 69) / 12)
        phase = 2 * np.pi * f * t + .045 * np.sin(2 * np.pi * .8 * t)
        sound = np.sin(phase) + .22 * np.sin(2 * phase) * np.exp(-t * 4)
        sound += .06 * np.sin(3 * phase) * np.exp(-t * 8)
        return sound * (1-np.exp(-t * (50 if soft else 150))) * np.exp(-t * (1.1 if soft else 2.3)) * np.minimum(1, (length-t)*20)

    for bar in range(16):
        chord = chords[bar % len(chords)]
        for chordbeat, gain in [(0,.105),(2.65,.065)]:
            for i, midi in enumerate(chord):
                place((bar*4+chordbeat)*beat+i*.018, note(midi,beat*2.5,True), gain, (i-2)*.25)
        for b in [0, 1.75, 3]:
            place((bar*4+b)*beat, note(chord[0]-24,beat*.9,True), .22)
        for b in [0, 1.5, 2.5]:
            t=np.arange(int(.28*RATE))/RATE
            kick=np.sin(2*np.pi*(45*t+2.5*(1-np.exp(-t*25))))*np.exp(-t*20)
            place((bar*4+b)*beat,kick,.26)
        for b in [1,3]:
            t=np.arange(int(.14*RATE))/RATE
            noise=rng.normal(0,1,len(t));noise=np.convolve(noise,np.ones(5)/5,'same')
            snare=(noise*.55+np.sin(2*np.pi*160*t)*.25)*np.exp(-t*35)
            place((bar*4+b)*beat+.013,snare,.12,-.1)
        for eighth in range(8):
            t=np.arange(int(.065*RATE))/RATE
            noise=rng.normal(0,1,len(t));noise-=np.convolve(noise,np.ones(15)/15,'same')
            place((bar*4+eighth*.5+(eighth%2)*.09)*beat,noise*np.exp(-t*90),.018 if eighth%2 else .028,.35)
        if bar % 4 != 3:
            for b, index in [(1.5,2),(2.5,3),(3.25,1)]:
                midi=chord[index]+12
                tone=note(midi,beat*1.5)
                place((bar*4+b)*beat,tone,.06,-.3)
                place((bar*4+b+.75)*beat,tone,.018,.4)
    # Quiet filtered texture, with circular smoothing for a continuous seam.
    noise=rng.normal(0,1,count)
    noise=(noise+np.roll(noise,1)+np.roll(noise,2))/3
    mix+=noise[:,None]*.0015
    mix=np.tanh(mix*1.25)
    mix*=.68/max(np.max(np.abs(mix)),.68)
    pcm=(mix*32767).astype('<i2')
    with tempfile.NamedTemporaryFile(suffix='.wav') as temp:
        with wave.open(temp.name,'wb') as w:
            w.setnchannels(2);w.setsampwidth(2);w.setframerate(RATE);w.writeframes(pcm.tobytes())
        subprocess.run(['ffmpeg','-v','error','-y','-i',temp.name,'-af','lowpass=f=6500','-codec:a','libmp3lame','-b:a','128k','-metadata','title='+title,'-metadata','artist=Alice original loops','-metadata','copyright=CC0-1.0',str(OUT/(name+'.mp3'))],check=True)
    return {'file':name+'.mp3','title':title,'bpm':bpm,'seconds':round(duration,3),'license':'CC0-1.0','seed':seed}


tracks = [
    compose('tide-window','窗边小潮汐',76,[[60,64,67,71,74],[57,60,64,67,71],[53,57,60,64,67],[55,59,62,65,69]],2026111901),
    compose('moon-postcard','月亮寄来的明信片',68,[[62,65,69,72,76],[55,59,62,65,69],[60,64,67,71,74],[57,60,64,67,71]],2026111902),
]
(OUT/'tracks.json').write_text(json.dumps({'authoring':'scripts/compose-lofi.py','sample_sources':'None; synthesized oscillators and seeded noise.','tracks':tracks},ensure_ascii=False,indent=2)+'\n')
print('Created',len(tracks),'original lo-fi loops.')
