"""Render the original one-shots as 24 kHz mono PCM."""
from array import array
from math import sin, cos, exp, pi
from pathlib import Path
from random import Random
import wave

out = Path(__file__).resolve().parents[1] / "Resources" / "Sounds"
sr = 24000
rng = Random(17)
tau = 2*pi
def sound(name, length, events):
    samples = [0.] * int(length*sr)
    for start, duration, tone in events:
        offset = int(start*sr)
        for i in range(min(int(duration*sr), len(samples)-offset)):
            t = i/sr
            env = min(1,t/.004,(duration-t)/.02)
            samples[offset+i] += tone(t)*env
    gain = .79/max(.001, max(abs(x) for x in samples))
    with wave.open(str(out/(name+".wav")), "wb") as w:
        w.setparams((1,2,sr,0,"NONE","not compressed"))
        w.writeframes(array("h",(int(x*gain*32767) for x in samples)).tobytes())

def reed(p):
    return sin(p)+.38*sin(2*p)+.22*sin(3*p)+.13*sin(5*p)
def boot(t):
    p=tau*(820*t+180*t*t+18*(1-cos(tau*3*t)))
    return (.8*sin(p)+.45*sin(2.42*p)+.15*rng.uniform(-1,1))*exp(-6*t)
sound("Boots",.85,[(0,.21,boot),(.27,.22,boot),(.59,.20,boot)])
sound("Bubbles",1.2,[(i*.10+(i%2)*.026,.18,
    lambda t,f=f: sin(tau*(f*t+1900*t*t))*exp(-24*t))
    for i,f in enumerate((400,760,500,900,630,1020,580,860,1240))])
sound("Foghorn",1.5,[(0,1.25,lambda t: min(1,t/.07)*min(1,(1.25-t)/.19)*(
    reed(tau*(89*t+.15*sin(tau*2*t)))+.68*reed(tau*112*t)))])
sound("Bonk",.66,[(0,.58,lambda t: (sin(tau*(97*t+4.5*(1-exp(-30*t))))+
    .52*sin(tau*446*t)*exp(-22*t))*exp(-9*t))])
sound("Womp",1.65,[(i*.29, .26 if i<3 else .72,
    lambda t,f=f: reed(tau*(f*t-12*t*t)+.16*sin(tau*5*t))*min(1,t/.035))
    for i,f in enumerate((277.2,261.6,246.9,196))])
sound("Rimshot",1.5,[(0,.17,lambda t:(.72*rng.uniform(-1,1)+sin(tau*172*t))*exp(-29*t)),
    (.20,.14,lambda t:(rng.uniform(-1,1)+sin(tau*195*t))*exp(-32*t)),
    (.35,1.14,lambda t:(.55*rng.uniform(-1,1)+.18*sin(tau*4261*t)+.2*sin(tau*2981*t))*exp(-4.7*t))])
sound("GameOver",1.12,[(i*.13,.13 if i<4 else .48,
    lambda t,f=f: (.72*sin(tau*f*t)+.24*sin(3*tau*f*t)+.14*sin(5*tau*f*t))*exp(-2*t))
    for i,f in enumerate((523.25,392,329.63,261.63,130.81))])
def pluck(f,slide=0):
    return lambda t: sum(sin(k*tau*(f*t+slide*t*t))*.66**(k-1)*exp(-(3+k*2)*t) for k in range(1,6))
sound("Lagoon",2.05,[(t,.75,pluck(f,slide)) for t,f,slide in
    [(0,261.63,0),(.015,329.63,0),(.03,392,0),(.19,523.25,-10),(.47,493.88,-55),
     (.70,392,0),(.85,349.23,0),(1.03,392,25),(1.25,261.63,0),(1.26,329.63,0),(1.27,392,0)]])

# Falling whistle, a beat of silence, then a tinny cascading crash.
sound("Anvil",1.9,[(0,.67,lambda t: .4*sin(tau*(1430*t-850*t*t))*(1-t)),
    (.84,.46,lambda t: (sin(tau*65*t)+.75*rng.uniform(-1,1))*exp(-16*t))] +
    [(t,.39,lambda u,f=f: (.6*sin(tau*f*u)+.4*sin(tau*f*1.56*u))*exp(-19*u))
     for t,f in [(.86,510),(.97,780),(1.12,632),(1.31,840),(1.53,1220)]])
# A lonely chirp answered from a different register after an uncomfortable pause.
sound("Crickets",2.32,[(t,.105,lambda u,f=f: sin(tau*f*u+.16*sin(tau*170*u))*
    (.5-.5*cos(tau*68*u))**2*min(1,u/.012,(.105-u)/.02))
    for t,f in [(0,3550),(.14,3580),(.28,3540),(1.32,2980),(1.47,3010),(1.62,2970),(2.12,3610)]])
# A feed motor labours, skips teeth, and gives up with an error chime.
sound("Printer",1.86,[(0,.58,lambda t: .25*reed(tau*(118*t+65*t*t))*(.6+.4*sin(tau*32*t))),
    (.59,.32,lambda t: .4*reed(tau*(230*t-250*t*t))*(.65+.35*sin(tau*19*t))),
    (.96,.25,lambda t: .45*rng.uniform(-1,1)*exp(-17*t)),
    (1.26,.15,lambda t: .42*sin(tau*784*t)),(1.48,.29,lambda t: .47*reed(tau*311*t)*exp(-6*t))])
