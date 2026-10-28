# Generates the synthesized WAV files in Sounds/: python tools/gen_sounds.py Sounds
import math, os, random, struct, sys, wave
RATE = 44100
random.seed(7)

def env_exp(t, dur, decay):
    return math.exp(-t * decay)

def render(dur, fn, peak=0.6):
    n = int(dur * RATE)
    s = [fn(i / RATE) for i in range(n)]
    fade = int(0.004 * RATE)
    for i in range(fade):
        s[i] *= i / fade
        s[n - 1 - i] *= i / fade
    m = max(abs(x) for x in s) or 1
    return [x / m * peak for x in s]

def save(path, samples):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in samples))

def tone(f, t, ph=0.0): return math.sin(2 * math.pi * f * t + ph)

def sweep(f0, f1, t, dur):
    # phase of a linear sweep
    k = (f1 - f0) / dur
    return math.sin(2 * math.pi * (f0 * t + 0.5 * k * t * t))

out = sys.argv[1]
# pulse sounds: short and unobtrusive, they repeat every 3 seconds
save(out + "/tick.wav", render(0.09, lambda t: (tone(1500, t) + 0.5 * tone(3000, t)) * env_exp(t, 0.09, 55)))
save(out + "/blip.wav", render(0.16, lambda t: (tone(660, t) + 0.3 * tone(1320, t)) * env_exp(t, 0.16, 22)))
# spawn sounds: noticeable, a totem just appeared
save(out + "/spawn-rise.wav", render(0.32, lambda t: sweep(350, 1100, t, 0.32) * min(1, (0.32 - t) * 14 + 0.2)))
def ding_dong(t):
    a = tone(784, t) * env_exp(t, 0.5, 9)
    b = tone(988, t - 0.17) * env_exp(t - 0.17, 0.5, 9) if t >= 0.17 else 0
    return a + b
save(out + "/spawn-ding.wav", render(0.55, ding_dong))
# destroyed sounds
def shatter(t):
    noise = random.uniform(-1, 1) * env_exp(t, 0.4, 11)
    thump = tone(90, t) * env_exp(t, 0.4, 14)
    return noise * 0.8 + thump
save(out + "/shatter.wav", render(0.4, shatter))
save(out + "/fall.wav", render(0.38, lambda t: sweep(700, 120, t, 0.38) * env_exp(t, 0.38, 4)))
# swells: rising runs of STEPS short sounds of STEP seconds (SWELL_STEPS / SWELL_STEP in Core.lua), the last ones played one
# after the other by the addon; each is a separate file so the addon can stop starting new ones when the totem
# dies. The last one is the loudest and ends on the pulse. Files: swell/<preset>/[alert-]<step>.wav
STEPS, STEP = 15, 0.2   # 15 steps = the whole 3 s between pulses; the addon plays the last few (setting "Swell length")

def render_raw(dur, fn):
    n = int(dur * RATE)
    s = [fn(i / RATE) for i in range(n)]
    fade = int(0.006 * RATE)
    for i in range(fade):
        s[i] *= i / fade
        s[n - 1 - i] *= i / fade
    return s

# calm levels are the plain rising runs below; the alert ones (played while an enemy has a fear, charm or sleep
# effect the pulse will remove) are a different, harsher sound per preset, further down
LEVELS = (("", 0.5),)   # file name part, volume scale

def gain(k): return 0.06 * 10 ** (k / (STEPS - 1))   # 0.06 .. 0.6, before the level's scale

# notes: a pentatonic run, each note fading out except the last
NOTES = [110, 131, 147, 165, 196, 220, 262, 294, 330, 392, 440, 523, 587, 659, 784]
for part, vol in LEVELS:
    for k, f in enumerate(NOTES):
        last = k == STEPS - 1
        def note(t, f=f, last=last):
            body = tone(f, t) + 0.25 * tone(2 * f, t)
            return body * (1.0 if last else math.exp(-t * 6))
        save(out + "/swell/notes/%s%d.wav" % (part, k + 1), render(STEP, note, gain(k) * vol))

# heartbeat: one soft low thump per step, getting higher and louder
for part, vol in LEVELS:
    for k in range(STEPS):
        f = 45 + 4 * k
        def thump(t, f=f):
            return (tone(f, t) + 0.4 * tone(2 * f, t)) * math.exp(-t * 14)
        save(out + "/swell/heartbeat/%s%d.wav" % (part, k + 1), render(STEP, thump, gain(k) * vol))

# alert versions: dramatic instead of just louder. Rough (many harmonics, detuned beating, tremolo), tense intervals.
AV = 1.5   # volume scale
def saw(f, t, n=6): return sum(tone(f * h, t) / h for h in range(1, n + 1))

# notes alert: a rising diminished run (tritones, minor seconds), rough detuned saws, sustained, last note a stab
ANOTES = [58, 82, 87, 117, 123, 165, 175, 233, 247, 330, 349, 466, 494, 659, 698]
for k, f in enumerate(ANOTES):
    last = k == STEPS - 1
    def anote(t, f=f, last=last):
        body = saw(f, t) + saw(f * 1.012, t) + (saw(f * 1.414, t, 4) if last else 0)
        return body * (1.0 if last else (1 - 0.5 * t / STEP)) * (0.75 + 0.25 * tone(28, t))
    save(out + "/swell/notes/alert-%d.wav" % (k + 1), render(STEP, anote, gain(k) * AV))

# heartbeat alert: a hard double thump (lub-dub) with a noisy attack, getting higher and faster-feeling
for k in range(STEPS):
    f = 50 + 5 * k
    def beat(t, f=f):
        def hit(tt):
            if tt < 0: return 0
            return (tone(f, tt) + 0.6 * tone(2 * f, tt) + 0.5 * random.uniform(-1, 1) * math.exp(-tt * 60)) * math.exp(-tt * 18)
        return hit(t) + 0.8 * hit(t - 0.09)
    save(out + "/swell/heartbeat/alert-%d.wav" % (k + 1), render(STEP, beat, gain(k) * AV))

# --- more presets. Each is a function (k, t) -> sample for the calm and for the alert version; k is the step 0..STEPS-1
# and i = k / (STEPS - 1) the intensity 0..1 (the render scales the step to gain(k)).
def noise(): return random.uniform(-1, 1)
def sq(f, t, n=5): return sum(tone(f * h, t) / h for h in range(1, n + 1, 2))   # soft square wave
FIFTHS = NOTES   # pentatonic frequencies, one per step
INTENSITY = lambda k: k / (STEPS - 1)

def drops(k, t):   # a water drop: a short upward chirp
    f0 = 420 + 500 * INTENSITY(k)
    return (sweep(f0, f0 * 1.7, t, 0.08) + 0.3 * tone(2 * f0, t)) * math.exp(-t * 35)
def drops_alert(k, t):   # two sharp, high double drops
    f0 = 900 + 700 * INTENSITY(k)
    def d(tt): return 0 if tt < 0 else (sweep(f0, f0 * 2.0, tt, 0.05) + 0.6 * tone(3 * f0, tt)) * math.exp(-tt * 30)
    return d(t) + 0.9 * d(t - 0.1)

def ticks(k, t):   # tick-tock of a clock, tock lower
    f = (900 if k % 2 else 720) + 500 * INTENSITY(k)
    return (tone(f, t) + 0.5 * noise() * math.exp(-t * 400)) * math.exp(-t * 55)
def ticks_alert(k, t):   # loud double clack with a low thud
    f = 1300 + 600 * INTENSITY(k)
    def c(tt): return 0 if tt < 0 else (sq(f, tt) + noise() * math.exp(-tt * 300)) * math.exp(-tt * 45)
    return c(t) + 0.8 * c(t - 0.08) + 0.7 * tone(110, t) * math.exp(-t * 25)

BELL = (1, 2.76, 5.40, 8.93)
def bells(k, t):   # a soft bell, pentatonic notes
    f = FIFTHS[k] * 2
    return sum(tone(f * r, t) * a for r, a in zip(BELL, (1, 0.5, 0.25, 0.12))) * math.exp(-t * 8)
def bells_alert(k, t):   # a clanging, dissonant bell: tritone pair, rough partials
    f = ANOTES[k] * 2
    return sum((tone(f * r, t) + tone(f * 1.414 * r, t)) * 0.5 for r in (1, 2.4, 4.1, 6.3, 9.1)) * math.exp(-t * 4) * (0.8 + 0.2 * tone(23, t))

def roll(k, t):   # soft toms; more hits per step as it goes
    n = 1 + int(INTENSITY(k) * 3.99)
    out = 0
    for h in range(n):
        tt = t - h * STEP / n
        if tt >= 0: out += (tone(95 + 50 * INTENSITY(k) - 40 * tt, tt) + 0.2 * noise()) * math.exp(-tt * 28)
    return out
def roll_alert(k, t):   # snare roll, noisy and dense
    n = 2 + int(INTENSITY(k) * 4.99)
    out = 0
    for h in range(n):
        tt = t - h * STEP / n
        if tt >= 0: out += (0.9 * noise() + 0.5 * tone(190, tt)) * math.exp(-tt * 30)
    return out

def sonar(k, t):   # a ping with an echo
    f = 800 + 400 * INTENSITY(k)
    e = 0.35 * tone(f, t - 0.1) * math.exp(-(t - 0.1) * 14) if t >= 0.1 else 0
    return tone(f, t) * math.exp(-t * 12) + e
def sonar_alert(k, t):   # buzzy double ping
    f = 1200 + 500 * INTENSITY(k)
    def p(tt): return 0 if tt < 0 else (tone(f, tt) + 0.6 * tone(2 * f, tt) + 0.4 * tone(3 * f + 7, tt)) * math.exp(-tt * 14)
    return p(t) + 0.9 * p(t - 0.09)

def arcade(k, t):   # soft chiptune: two square blips, a fifth apart
    f = FIFTHS[k] * 2
    h = t >= STEP / 2
    tt = t - (STEP / 2 if h else 0)
    return sq(f * (1.5 if h else 1), tt) * math.exp(-tt * 12)
def arcade_alert(k, t):   # harsh sawtooth arpeggio over a diminished chord
    f = FIFTHS[k] * 2
    q = STEP / 4
    j = min(int(t / q), 3)
    tt = t - j * q
    return saw(f * (1, 1.189, 1.414, 1.682)[j], tt) * math.exp(-tt * 8)

PRESETS = { "drops": (drops, drops_alert), "ticks": (ticks, ticks_alert), "bells": (bells, bells_alert),
            "roll": (roll, roll_alert), "sonar": (sonar, sonar_alert), "arcade": (arcade, arcade_alert) }
for name, (calm, alert) in PRESETS.items():
    for k in range(STEPS):
        save(out + "/swell/%s/%d.wav" % (name, k + 1), render(STEP, lambda t, k=k: calm(k, t), gain(k) * LEVELS[0][1]))
        save(out + "/swell/%s/alert-%d.wav" % (name, k + 1), render(STEP, lambda t, k=k: alert(k, t), gain(k) * AV))
print("ok")
