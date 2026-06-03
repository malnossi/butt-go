export namespace audio {
	
	export class Device {
	    index: number;
	    name: string;
	
	    static createFrom(source: any = {}) {
	        return new Device(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.index = source["index"];
	        this.name = source["name"];
	    }
	}

}

export namespace main {
	
	export class StreamParams {
	    deviceIndex: number;
	    channels: number;
	    sampleRate: number;
	    bitrate: number;
	    codec: string;
	    host: string;
	    mountPoint: string;
	    username: string;
	    password: string;
	    streamName: string;
	    description: string;
	    genre: string;
	    url: string;
	    public: boolean;
	
	    static createFrom(source: any = {}) {
	        return new StreamParams(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.deviceIndex = source["deviceIndex"];
	        this.channels = source["channels"];
	        this.sampleRate = source["sampleRate"];
	        this.bitrate = source["bitrate"];
	        this.codec = source["codec"];
	        this.host = source["host"];
	        this.mountPoint = source["mountPoint"];
	        this.username = source["username"];
	        this.password = source["password"];
	        this.streamName = source["streamName"];
	        this.description = source["description"];
	        this.genre = source["genre"];
	        this.url = source["url"];
	        this.public = source["public"];
	    }
	}

}

