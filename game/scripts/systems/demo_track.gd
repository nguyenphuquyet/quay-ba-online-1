class_name QBODemoTrack
extends RefCounted
## Sinh track demo gốc (124 BPM) bằng tổng hợp tín hiệu — không dùng nhạc bên thứ ba.
## Track giống hệt nhau trên mọi máy nên có thể đồng bộ vị trí phát.

const BPM := 124.0


static func generate(sample_rate := 32000, seconds := 12.0) -> AudioStreamWAV:
	var total := int(sample_rate * seconds)
	var data := PackedByteArray()
	data.resize(total * 2)
	var beat_dur := 60.0 / BPM
	var bass_notes := [55.0, 55.0, 73.42, 65.41, 55.0, 82.41, 73.42, 61.74]
	var chord_notes := [220.0, 261.63, 329.63, 293.66]
	for i in total:
		var t := float(i) / float(sample_rate)
		var beat := t / beat_dur
		var beat_phase := fmod(beat, 1.0)
		var bar := int(beat / 4.0) % bass_notes.size()

		# Kick.
		var kick_env: float = exp(-beat_phase * 16.0)
		var kick_freq: float = 46.0 + 90.0 * exp(-beat_phase * 24.0)
		var kick: float = sin(TAU * kick_freq * t) * kick_env

		# Bass line (nốt đổi mỗi phẩy).
		var bass_freq: float = bass_notes[bar]
		var bass_env: float = 0.5 + 0.5 * sin(TAU * (beat * 0.5))
		var bass: float = sin(TAU * bass_freq * t) * 0.22 * bass_env
		bass += sin(TAU * bass_freq * 2.0 * t) * 0.06 * bass_env

		# Hi-hat mỗi 1/8.
		var eighth_phase: float = fmod(beat * 2.0, 1.0)
		var hat_env: float = exp(-eighth_phase * 45.0)
		var noise := sin(t * 17331.0) * sin(t * 9287.0)
		var hat: float = noise * hat_env * 0.045

		# Pad hợp âm, vào dần ở cuối mỗi 4 phách.
		var pad := 0.0
		var chord_index := int(beat / 8.0) % chord_notes.size()
		for n in range(4):
			var freq: float = chord_notes[(chord_index + n) % chord_notes.size()]
			pad += sin(TAU * freq * t) * 0.012 * (0.6 + 0.4 * sin(TAU * t / seconds))
		# Snare nhẹ ở phách 2 và 4.
		var snare := 0.0
		var beat_index := int(beat) % 4
		if beat_index == 1 or beat_index == 3:
			snare = noise * exp(-beat_phase * 22.0) * 0.07

		var sample: float = kick * 0.5 + bass + hat + pad + snare
		sample = clampf(sample, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 30000.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = total
	return stream
