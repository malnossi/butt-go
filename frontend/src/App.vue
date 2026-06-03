<script setup>
import { ref, onMounted, onUnmounted, watch } from 'vue'
import { GetInputDevices, StartStream, StopStream } from '../wailsjs/go/main/App'
import { EventsOn, EventsOff } from '../wailsjs/runtime'

// Tabs & UI state
const activeTab = ref('server')
const showPassword = ref(false)
const showSettings = ref(false)

// Devices & State
const devices = ref([])
const selectedDeviceIndex = ref(0)
const status = ref('disconnected') // disconnected, connecting, connected, reconnecting
const statusMsg = ref('Ready to stream')

const toast = ref({ visible: false, message: '', type: 'error' })
let toastTimer = null

const showToast = (message, type = 'error') => {
  toast.value = { visible: true, message, type }
  if (toastTimer) clearTimeout(toastTimer)
  toastTimer = setTimeout(() => {
    toast.value.visible = false
  }, 5000)
}

// VU Meter & Peaks
const vuLeft = ref(0)
const vuRight = ref(0)
const peakLeft = ref(0)
const peakRight = ref(0)
const dbLeft = ref(-80)
const dbRight = ref(-80)

// Stats
const bytesSent = ref(0)
const uptime = ref(0)



// Default Configuration
const streamConfig = ref({
  serverHost: 'localhost',
  serverPort: '8000',
  mountPoint: '/live',
  username: 'source',
  password: 'hackme',
  streamName: 'Atheer Live',
  description: 'Broadcasting live using Atheer client',
  genre: 'Live',
  url: 'http://localhost/',
  public: false,
  channels: 2,
  sampleRate: 44100,
  codec: 'mp3',
  bitrate: 128,
  aacProfile: 'lc',
  opusApp: 'audio',
  vorbisQuality: '0.7'
})



// Convert RMS [0.0 - 1.0] to Decibels [-80dB - 0dB]
const rmsToDb = (rms) => {
  if (rms <= 0.0001) return -80
  return 20 * Math.log10(rms)
}

// Map dB value to meter percentage [0% - 100%]
const dbToPercent = (db) => {
  if (db <= -60) return 0
  if (db >= 0) return 100
  const norm = (db + 60) / 60
  return Math.pow(norm, 1.5) * 100
}

// Format network bytes
const formatBytes = (bytes) => {
  if (!bytes) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

// Format connection uptime
const formatUptime = (secs) => {
  if (!secs) return '00:00:00'
  const h = Math.floor(secs / 3600)
  const m = Math.floor((secs % 3600) / 60)
  const s = Math.floor(secs % 60)
  return [
    h.toString().padStart(2, '0'),
    m.toString().padStart(2, '0'),
    s.toString().padStart(2, '0')
  ].join(':')
}

// Toggle Stream connection
const toggleStream = async () => {
  if (status.value === 'connected' || status.value === 'reconnecting' || status.value === 'connecting') {
    await StopStream()
    // Reset levels visually
    vuLeft.value = 0
    vuRight.value = 0
    peakLeft.value = 0
    peakRight.value = 0
    dbLeft.value = -80
    dbRight.value = -80
    return
  }

  try {
    const combinedHost = `${streamConfig.value.serverHost}:${streamConfig.value.serverPort}`
    
    await StartStream({
      deviceIndex: parseInt(selectedDeviceIndex.value),
      channels: parseInt(streamConfig.value.channels),
      sampleRate: parseInt(streamConfig.value.sampleRate),
      codec: streamConfig.value.codec,
      bitrate: parseInt(streamConfig.value.bitrate),
      host: combinedHost,
      mountPoint: streamConfig.value.mountPoint,
      username: streamConfig.value.username,
      password: streamConfig.value.password,
      streamName: streamConfig.value.streamName,
      description: streamConfig.value.description,
      genre: streamConfig.value.genre,
      url: streamConfig.value.url,
      public: streamConfig.value.public
    })
  } catch (err) {
    showToast(`Streaming setup failed: ${err}`, 'error')
  }
}

// Event Listeners setup
onMounted(async () => {
  // Query available device list
  try {
    const list = await GetInputDevices()
    devices.value = list
    if (list.length > 0) {
      selectedDeviceIndex.value = list[0].index
    }
  } catch (err) {
    showToast(`Failed to scan audio inputs: ${err}`, 'error')
  }

  watch(() => streamConfig.value.codec, (newVal) => {
    if (newVal === 'opus') {
      streamConfig.value.sampleRate = 48000
    }
  })

  // Bind connection state changes
  EventsOn('stream-state', (data) => {
    status.value = data.state
    statusMsg.value = data.message

    if (data.message.toLowerCase().includes('failed') || data.message.toLowerCase().includes('error')) {
      showToast(data.message, 'error')
    }
  })

  let animationFrameId = null
  let targetVuLeft = 0
  let targetVuRight = 0

  // Hardware accelerated 60fps render loop
  const renderLoop = () => {
    // Lerp factor (higher is faster snap, lower is smoother glide)
    const lerp = 0.25

    // Smoothly interpolate current VU value towards target
    vuLeft.value += (targetVuLeft - vuLeft.value) * lerp
    vuRight.value += (targetVuRight - vuRight.value) * lerp

    // Cap at minimum 0 to avoid floating point drift below zero
    if (vuLeft.value < 0.1) vuLeft.value = 0
    if (vuRight.value < 0.1) vuRight.value = 0

    // Smooth peak hold decay directly in the 60fps loop
    if (vuLeft.value > peakLeft.value) {
      peakLeft.value = vuLeft.value
    } else {
      peakLeft.value = Math.max(0, peakLeft.value - 0.4) // 60fps decay rate
    }

    if (vuRight.value > peakRight.value) {
      peakRight.value = vuRight.value
    } else {
      peakRight.value = Math.max(0, peakRight.value - 0.4) // 60fps decay rate
    }

    animationFrameId = requestAnimationFrame(renderLoop)
  }

  // Start the render loop
  animationFrameId = requestAnimationFrame(renderLoop)

  // Bind low-frequency (15Hz) audio level telemetry
  EventsOn('audio-level', (data) => {
    // Sync state
    if (data.state && status.value !== data.state) {
      status.value = data.state
    }

    // Convert and scale raw RMS audio levels
    const leftDb = rmsToDb(data.left)
    const rightDb = rmsToDb(data.right)
    dbLeft.value = leftDb
    dbRight.value = rightDb

    // Update targets for the 60fps render loop to lerp towards
    targetVuLeft = dbToPercent(leftDb)
    targetVuRight = dbToPercent(rightDb)

    // Network & time telemetry
    bytesSent.value = data.bytesSent
    uptime.value = data.uptime
  })
})

onUnmounted(() => {
  if (animationFrameId) {
    cancelAnimationFrame(animationFrameId)
  }
  EventsOff('stream-state')
  EventsOff('audio-level')
})
</script>

<template>
  <div id="app" :class="{'is-broadcasting': status === 'connected'}">
    <!-- Toast Notification -->
    <transition name="toast-fade">
      <div v-if="toast.visible" :class="['toast', toast.type]">
        <svg v-if="toast.type === 'error'" style="width:20px;height:20px;margin-right:8px;" viewBox="0 0 24 24">
          <path fill="currentColor" d="M12,20C7.59,20 4,16.41 4,12C4,7.59 7.59,4 12,4C16.41,4 20,7.59 20,12C20,16.41 16.41,20 12,20M12,2C6.47,2 2,6.47 2,12C2,17.53 6.47,22 12,22C17.53,22 22,17.53 22,12C22,6.47 17.53,2 12,2M11,14V16H13V14H11M11,8V12H13V8H11Z" />
        </svg>
        <span>{{ toast.message }}</span>
        <button class="toast-close" @click="toast.visible = false">
          <svg style="width:16px;height:16px" viewBox="0 0 24 24">
            <path fill="currentColor" d="M19,6.41L17.59,5L12,10.59L6.41,5L5,6.41L10.59,12L5,17.59L6.41,19L12,13.41L17.59,19L19,17.59L13.41,12L19,6.41Z" />
          </svg>
        </button>
      </div>
    </transition>

    <main class="dashboard">
      <!-- Top Bar -->
      <div class="top-controls">
        <div class="brand">ATHEER</div>
        <button class="settings-btn" @click="showSettings = true" aria-label="Settings">
          <svg style="width:28px;height:28px" viewBox="0 0 24 24">
            <path fill="currentColor" d="M12,15.5A3.5,3.5 0 0,1 8.5,12A3.5,3.5 0 0,1 12,8.5A3.5,3.5 0 0,1 15.5,12A3.5,3.5 0 0,1 12,15.5M19.43,12.97C19.47,12.65 19.5,12.33 19.5,12C19.5,11.67 19.47,11.34 19.43,11L21.54,9.37C21.73,9.22 21.78,8.95 21.66,8.73L19.66,5.27C19.54,5.05 19.27,4.96 19.05,5.05L16.56,6.05C16.04,5.66 15.47,5.34 14.86,5.08L14.47,2.42C14.43,2.18 14.22,2 13.97,2H9.97C9.72,2 9.51,2.18 9.47,2.42L9.08,5.08C8.47,5.34 7.9,5.66 7.38,6.05L4.89,5.05C4.67,4.96 4.4,5.05 4.27,5.27L2.27,8.73C2.15,8.95 2.2,9.22 2.39,9.37L4.5,11C4.47,11.34 4.44,11.67 4.44,12C4.44,12.33 4.47,12.65 4.5,12.97L2.39,14.63C2.2,14.78 2.15,15.05 2.27,15.27L4.27,18.73C4.4,18.95 4.67,19.04 4.89,18.95L7.38,17.95C7.9,18.34 8.47,18.66 9.08,18.92L9.47,21.58C9.51,21.82 9.72,22 9.97,22H13.97C14.22,22 14.43,21.82 14.47,21.58L14.86,18.92C15.47,18.66 16.04,18.34 16.56,17.95L19.05,18.95C19.27,19.04 19.54,18.95 19.66,18.73L21.66,15.27C21.78,15.05 21.73,14.78 21.54,14.63L19.43,12.97Z" />
          </svg>
        </button>
      </div>

      <!-- Middle Section -->
      <div class="middle-section">
        <!-- Left Column: VU Meters -->
        <section class="vu-meters-panel">
          <div class="vu-rack-vertical">
            <div class="vu-meter-strip">
              <!-- Left Channel Track -->
              <div class="vu-channel-column">
                <div class="vu-channel-track">
                  <div class="vu-channel-fill" :style="{ height: vuLeft + '%' }"></div>
                  <div class="vu-channel-peak" :style="{ bottom: peakLeft + '%' }"></div>
                </div>
              </div>

              <!-- Scale Ticks Column -->
              <div class="vu-scale-ticks">
                <div class="ticks-container">
                  <div class="tick" style="bottom: 100%"><span>0</span></div>
                  <div class="tick" style="bottom: 87.8%"><span>-5</span></div>
                  <div class="tick" style="bottom: 76.1%"><span>-10</span></div>
                  <div class="tick" style="bottom: 54.4%"><span>-20</span></div>
                  <div class="tick" style="bottom: 35.4%"><span>-30</span></div>
                  <div class="tick" style="bottom: 19.2%"><span>-40</span></div>
                  <div class="tick" style="bottom: 6.8%"><span>-50</span></div>
                  <div class="tick" style="bottom: 0%"><span>-60</span></div>
                </div>
              </div>

              <!-- Right Channel Track -->
              <div class="vu-channel-column" v-if="streamConfig.channels == 2">
                <div class="vu-channel-track">
                  <div class="vu-channel-fill" :style="{ height: vuRight + '%' }"></div>
                  <div class="vu-channel-peak" :style="{ bottom: peakRight + '%' }"></div>
                </div>
              </div>
            </div>
          </div>
        </section>

        <!-- Right Column: Dashboard Controls -->
        <section class="info-panel">
          <div class="center-stage">
            <div class="on-air-indicator" :class="{ active: status === 'connected' }">
              ON AIR
            </div>

            <div class="status-display">
              <div class="status-text" :class="status">{{ statusMsg }}</div>
            </div>
          </div>

          <div class="telemetry-grid">
            <div class="telemetry-box">
              <span class="label">UPTIME</span>
              <span class="value">{{ formatUptime(uptime) }}</span>
            </div>
            <div class="telemetry-box">
              <span class="label">DATA</span>
              <span class="value">{{ formatBytes(bytesSent) }}</span>
            </div>
          </div>
        </section>
      </div>

      <!-- Bottom Broadcast Button -->
      <div class="bottom-controls">
        <button 
          class="giant-broadcast-btn" 
          :class="status"
          @click="toggleStream"
        >
          <span v-if="status === 'disconnected' || status === 'error'">START BROADCAST</span>
          <span v-else-if="status === 'connecting'">CONNECTING...</span>
          <span v-else-if="status === 'reconnecting'">RECONNECTING...</span>
          <span v-else>STOP BROADCAST</span>
        </button>
      </div>
    </main>

    <!-- Settings Overlay and Drawer -->
    <div class="settings-overlay" :class="{ active: showSettings }" @click="showSettings = false"></div>
    <div class="settings-drawer" :class="{ open: showSettings }">
      <div class="drawer-header">
        <h2>System Configuration</h2>
        <button class="close-btn" @click="showSettings = false">
          <svg style="width:24px;height:24px" viewBox="0 0 24 24">
            <path fill="currentColor" d="M19,6.41L17.59,5L12,10.59L6.41,5L5,6.41L10.59,12L5,17.59L6.41,19L12,13.41L17.59,19L19,17.59L13.41,12L19,6.41Z" />
          </svg>
        </button>
      </div>

      <div class="drawer-content">
        <!-- Device Selector -->
        <div class="form-group" style="margin-bottom: 24px;">
          <label for="device">Audio Capture Device</label>
          <select 
            id="device" 
            v-model="selectedDeviceIndex" 
            class="form-control" 
            :disabled="status !== 'disconnected'"
          >
            <option 
              v-for="dev in devices" 
              :key="dev.index" 
              :value="dev.index"
            >
              {{ dev.name }}
            </option>
            <option v-if="devices.length === 0" disabled>No inputs found</option>
          </select>
        </div>

        <!-- Settings Tabs -->
        <div class="tab-headers">
          <button 
            :class="['tab-btn', { active: activeTab === 'server' }]" 
            @click="activeTab = 'server'"
          >
            Server
          </button>
          <button 
            :class="['tab-btn', { active: activeTab === 'audio' }]" 
            @click="activeTab = 'audio'"
          >
            Audio Quality
          </button>
        </div>

        <!-- Tab Contents -->
        <div class="tab-content-container">
          <!-- Server Tab -->
          <div v-if="activeTab === 'server'" class="settings-grid">
            <div class="form-row" style="grid-template-columns: 2fr 1fr;">
              <div class="form-group">
                <label for="serverHost">Server Address</label>
                <input 
                  id="serverHost" 
                  v-model="streamConfig.serverHost" 
                  type="text" 
                  class="form-control" 
                  placeholder="e.g. 127.0.0.1"
                  :disabled="status !== 'disconnected'"
                />
              </div>
              <div class="form-group">
                <label for="serverPort">Port</label>
                <input 
                  id="serverPort" 
                  v-model="streamConfig.serverPort" 
                  type="text" 
                  class="form-control" 
                  placeholder="8000"
                  :disabled="status !== 'disconnected'"
                />
              </div>
            </div>

            <div class="form-row">
              <div class="form-group">
                <label for="mount">Mountpoint</label>
                <input 
                  id="mount" 
                  v-model="streamConfig.mountPoint" 
                  type="text" 
                  class="form-control" 
                  placeholder="e.g. /live"
                  :disabled="status !== 'disconnected'"
                />
              </div>
              <div class="form-group">
                <label for="user">Username</label>
                <input 
                  id="user" 
                  v-model="streamConfig.username" 
                  type="text" 
                  class="form-control" 
                  placeholder="source"
                  :disabled="status !== 'disconnected'"
                />
              </div>
            </div>

            <div class="form-row">
              <div class="form-group">
                <label for="pass">Source Password</label>
                <div class="password-input-wrapper">
                  <input 
                    id="pass" 
                    v-model="streamConfig.password" 
                    :type="showPassword ? 'text' : 'password'" 
                    class="form-control" 
                    placeholder="Password"
                    :disabled="status !== 'disconnected'"
                  />
                  <button 
                    type="button" 
                    class="btn-toggle-password" 
                    @click="showPassword = !showPassword"
                    :disabled="status !== 'disconnected'"
                  >
                    <svg v-if="showPassword" style="width:16px;height:16px" viewBox="0 0 24 24">
                      <path fill="currentColor" d="M2,5.27L3.28,4L20,20.72L18.73,22L15.65,18.92C14.5,19.3 13.28,19.5 12,19.5C7,19.5 2.73,16.39 1,12C1.69,10.24 2.78,8.68 4.21,7.47L2,5.27M12,9A3,3 0 0,1 15,12C15,12.35 14.94,12.69 14.83,13L11,9.17C11.31,9.06 11.65,9 12,9M12,4.5C17,4.5 21.27,7.61 23,12C22.18,14.08 20.79,15.89 19,17.19L17.58,15.76C18.94,14.82 20.06,13.5 20.54,12C19.06,8.27 15.3,5.78 11,5.78C9.83,5.78 8.7,6 7.67,6.33L6.12,4.78C7.96,4.16 9.94,3.78 12,3.78M8.82,10.59L11.41,13.18C10.79,13.29 10.15,13.06 9.71,12.62C9.27,12.18 9.04,11.54 9.15,10.92" />
                    </svg>
                    <svg v-else style="width:16px;height:16px" viewBox="0 0 24 24">
                      <path fill="currentColor" d="M12,9A3,3 0 0,0 9,12A3,3 0 0,0 12,15A3,3 0 0,0 15,12A3,3 0 0,0 12,9M12,4.5C7,4.5 2.73,7.61 1,12C2.73,16.39 7,19.5 12,19.5C17,19.5 21.27,16.39 23,12C21.27,7.61 17,4.5 12,4.5M12,17A5,5 0 0,1 7,12A5,5 0 0,1 12,7A5,5 0 0,1 17,12A5,5 0 0,1 12,17Z" />
                    </svg>
                  </button>
                </div>
              </div>
              <div class="form-group">
                <label for="genre">Genre</label>
                <input 
                  id="genre" 
                  v-model="streamConfig.genre" 
                  type="text" 
                  class="form-control" 
                  placeholder="Live, Rock, News"
                  :disabled="status !== 'disconnected'"
                />
              </div>
            </div>

            <div class="form-group">
              <label for="stream-name">Station Name</label>
              <input 
                id="stream-name" 
                v-model="streamConfig.streamName" 
                type="text" 
                class="form-control" 
                placeholder="Station Title"
                :disabled="status !== 'disconnected'"
              />
            </div>

            <div class="form-group checkbox-group" style="margin-top: 10px;">
              <input 
                id="public" 
                v-model="streamConfig.public" 
                type="checkbox" 
                :disabled="status !== 'disconnected'"
              />
              <label for="public">Publish to Directory</label>
            </div>
          </div>

          <!-- Audio Tab -->
          <div v-if="activeTab === 'audio'" class="settings-grid">
            <div class="form-row">
              <div class="form-group">
                <label for="codec">Audio Codec</label>
                <select 
                  id="codec" 
                  v-model="streamConfig.codec" 
                  class="form-control" 
                  :disabled="status !== 'disconnected'"
                >
                  <option value="mp3">MP3 (MPEG)</option>
                  <option value="aac">AAC (Advanced Audio)</option>
                  <option value="opus">Opus (Interactive)</option>
                  <option value="vorbis">Ogg Vorbis</option>
                </select>
              </div>

              <div class="form-group">
                <label for="bitrate">Bitrate</label>
                <select 
                  id="bitrate" 
                  v-model="streamConfig.bitrate" 
                  class="form-control" 
                  :disabled="status !== 'disconnected'"
                >
                  <option :value="320">320 kbps</option>
                  <option :value="256">256 kbps</option>
                  <option :value="192">192 kbps</option>
                  <option :value="128">128 kbps</option>
                  <option :value="96">96 kbps</option>
                  <option :value="64">64 kbps</option>
                </select>
              </div>
            </div>

            <div class="form-row">
              <div class="form-group">
                <label for="channels">Channels</label>
                <select 
                  id="channels" 
                  v-model="streamConfig.channels" 
                  class="form-control" 
                  :disabled="status !== 'disconnected'"
                >
                  <option :value="1">1 - Mono</option>
                  <option :value="2">2 - Stereo</option>
                </select>
              </div>

              <div class="form-group">
                <label for="sample-rate">Sample Rate</label>
                <select 
                  id="sample-rate" 
                  v-model="streamConfig.sampleRate" 
                  class="form-control" 
                  :disabled="status !== 'disconnected' || streamConfig.codec === 'opus'"
                >
                  <option :value="48000">48000 Hz</option>
                  <option :value="44100">44100 Hz</option>
                  <option :value="32000">32000 Hz</option>
                  <option :value="22050">22050 Hz</option>
                </select>
              </div>
            </div>

            <!-- Codec-specific -->
            <div class="form-row" v-if="streamConfig.codec === 'aac'">
              <div class="form-group">
                <label for="aac-profile">AAC Profile</label>
                <select 
                  id="aac-profile" 
                  v-model="streamConfig.aacProfile" 
                  class="form-control" 
                  :disabled="status !== 'disconnected'"
                >
                  <option value="lc">AAC-LC (Low Complexity)</option>
                  <option value="he">HE-AAC (High Efficiency)</option>
                </select>
              </div>
            </div>

            <div class="form-row" v-if="streamConfig.codec === 'opus'">
              <div class="form-group">
                <label for="opus-app">Opus Application</label>
                <select 
                  id="opus-app" 
                  v-model="streamConfig.opusApp" 
                  class="form-control" 
                  :disabled="status !== 'disconnected'"
                >
                  <option value="audio">Audio (General/Music)</option>
                  <option value="voip">VoIP (Voice over IP)</option>
                  <option value="lowdelay">Low Delay (Real-time)</option>
                </select>
              </div>
            </div>

            <div class="form-row" v-if="streamConfig.codec === 'vorbis'">
              <div class="form-group">
                <label for="vorbis-quality">VBR Quality</label>
                <select 
                  id="vorbis-quality" 
                  v-model="streamConfig.vorbisQuality" 
                  class="form-control" 
                  :disabled="status !== 'disconnected'"
                >
                  <option value="1.0">High (q=1.0)</option>
                  <option value="0.7">Standard (q=0.7)</option>
                  <option value="0.4">Low (q=0.4)</option>
                </select>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
