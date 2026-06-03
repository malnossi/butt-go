package main

import (
	"context"
	"time"

	"atheer/internal/audio"
	"atheer/internal/engine"
	"atheer/internal/streamer"
	"slices"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// StreamParams maps the configuration received from the Vue frontend.
type StreamParams struct {
	DeviceIndex int    `json:"deviceIndex"`
	Channels    int    `json:"channels"`
	SampleRate  int    `json:"sampleRate"`
	Bitrate     int    `json:"bitrate"`
	Codec       string `json:"codec"`
	Host        string `json:"host"`
	MountPoint  string `json:"mountPoint"`
	Username    string `json:"username"`
	Password    string `json:"password"`
	StreamName  string `json:"streamName"`
	Description string `json:"description"`
	Genre       string `json:"genre"`
	URL         string `json:"url"`
	Public      bool   `json:"public"`
}

// App struct manages the frontend integration.
type App struct {
	ctx    context.Context
	engine *engine.Engine
}

// NewApp creates a new App application struct.
func NewApp() *App {
	a := &App{}
	a.engine = engine.NewEngine(func(state engine.EngineState, message string) {
		if a.ctx != nil {
			runtime.EventsEmit(a.ctx, "stream-state", map[string]interface{}{
				"state":   string(state),
				"message": message,
			})
		}
	})
	return a
}

// startup is called when the app starts. The context is saved
// and the VU ticker is started.
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	go a.startVUTicker()
}

// GetInputDevices queries all available audio input devices.
func (a *App) GetInputDevices() ([]audio.Device, error) {
	seq, err := audio.GetInputDevices()
	if err != nil {
		return nil, err
	}
	return slices.Collect(seq), nil
}

// StartStream initializes audio recording and streams MP3 frames to Icecast.
func (a *App) StartStream(p StreamParams) error {
	cfg := streamer.Config{
		Host:        p.Host,
		MountPoint:  p.MountPoint,
		Username:    p.Username,
		Password:    p.Password,
		StreamName:  p.StreamName,
		Description: p.Description,
		Genre:       p.Genre,
		URL:         p.URL,
		Public:      p.Public,
		Bitrate:     p.Bitrate,
		SampleRate:  p.SampleRate,
		Channels:    p.Channels,
		Codec:       p.Codec,
	}
	return a.engine.StartStream(p.DeviceIndex, cfg)
}

// StopStream stops the live stream and releases PortAudio/LAME resources.
func (a *App) StopStream() {
	a.engine.StopStream()
}

// startVUTicker periodically broadcasts audio levels and connection uptime at 15Hz.
func (a *App) startVUTicker() {
	ticker := time.NewTicker(66 * time.Millisecond) // ~15 FPS
	defer ticker.Stop()

	idleFrames := 0

	for {
		select {
		case <-a.ctx.Done():
			return
		case <-ticker.C:
			left, right := a.engine.GetLevels()
			stats := a.engine.GetStats()

			// Throttle IPC events to save CPU when the app is idle/disconnected
			if stats.State == engine.StateDisconnected && left == 0 && right == 0 {
				idleFrames++
				if idleFrames > 50 { // ~3.3 seconds of silence & disconnected
					ticker.Reset(500 * time.Millisecond)
				}
			} else {
				if idleFrames > 50 {
					ticker.Reset(66 * time.Millisecond)
				}
				idleFrames = 0
			}

			runtime.EventsEmit(a.ctx, "audio-level", map[string]interface{}{
				"left":      left,
				"right":     right,
				"bytesSent": stats.BytesSent,
				"uptime":    stats.Uptime,
				"state":     string(stats.State),
			})
		}
	}
}
