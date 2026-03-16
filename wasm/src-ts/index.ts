import { Vec3 as WasmVec3, Block as WasmBlock, BlockEvent as WasmBlockEvent } from '../pkg/mcpi_wasm';

/**
 * Vector3 representation for coordinates
 */
export class Vec3 {
    public x: number;
    public y: number;
    public z: number;

    constructor(x: number = 0, y: number = 0, z: number = 0) {
        this.x = x;
        this.y = y;
        this.z = z;
    }

    /**
     * Get the length of the vector
     */
    length(): number {
        return Math.sqrt(this.lengthSquared());
    }

    /**
     * Get the squared length of the vector
     */
    lengthSquared(): number {
        return this.x * this.x + this.y * this.y + this.z * this.z;
    }

    /**
     * Add another vector
     */
    add(rhs: Vec3): Vec3 {
        const c = this.clone();
        c.x += rhs.x;
        c.y += rhs.y;
        c.z += rhs.z;
        return c;
    }

    /**
     * Multiply by a scalar
     */
    multiply(scalar: number): Vec3 {
        const c = this.clone();
        c.x *= scalar;
        c.y *= scalar;
        c.z *= scalar;
        return c;
    }

    /**
     * Clone this vector
     */
    clone(): Vec3 {
        return new Vec3(this.x, this.y, this.z);
    }

    /**
     * Negate the vector
     */
    negate(): Vec3 {
        return new Vec3(-this.x, -this.y, -this.z);
    }

    /**
     * Subtract another vector
     */
    subtract(rhs: Vec3): Vec3 {
        return this.add(rhs.negate());
    }

    /**
     * Round to integer coordinates
     */
    round(): void {
        this.x = Math.round(this.x);
        this.y = Math.round(this.y);
        this.z = Math.round(this.z);
    }

    /**
     * Floor to integer coordinates
     */
    floor(): void {
        this.x = Math.floor(this.x);
        this.y = Math.floor(this.y);
        this.z = Math.floor(this.z);
    }

    toString(): string {
        return `Vec3(${this.x},${this.y},${this.z})`;
    }
}

/**
 * Block representation
 */
export class Block {
    public id: number;
    public data: number;

    constructor(id: number, data: number = 0) {
        this.id = id;
        this.data = data;
    }

    /**
     * Create a new block with different data
     */
    withData(data: number): Block {
        return new Block(this.id, data);
    }

    toString(): string {
        return `Block(${this.id}, ${this.data})`;
    }

    [Symbol.iterator](): Iterator<number> {
        return [this.id, this.data][Symbol.iterator]();
    }
}

/**
 * Block event types
 */
export enum BlockEventType {
    HIT = 0,
}

/**
 * Block event
 */
export class BlockEvent {
    public type: BlockEventType;
    public pos: Vec3;
    public face: number;
    public entityId: number;

    constructor(
        type: BlockEventType,
        x: number,
        y: number,
        z: number,
        face: number,
        entityId: number
    ) {
        this.type = type;
        this.pos = new Vec3(x, y, z);
        this.face = face;
        this.entityId = entityId;
    }

    static hit(x: number, y: number, z: number, face: number, entityId: number): BlockEvent {
        return new BlockEvent(BlockEventType.HIT, x, y, z, face, entityId);
    }

    toString(): string {
        return `BlockEvent(${this.type}, ${this.pos.x}, ${this.pos.y}, ${this.pos.z}, ${this.face}, ${this.entityId})`;
    }
}

/**
 * Connection error
 */
export class RequestError extends Error {
    constructor(message: string) {
        super(message);
        this.name = 'RequestError';
    }
}

/**
 * Connection to a Minecraft server
 */
export class Connection {
    private socket: WebSocket | null = null;
    private address: string;
    private port: number;
    private lastSent: string = '';
    private messageQueue: Array<{ resolve: Function; reject: Function }> = [];
    private messageBuffer: string = '';

    constructor(address: string, port: number) {
        this.address = address;
        this.port = port;
    }

    /**
     * Connect to the Minecraft server
     */
    async connect(): Promise<void> {
        return new Promise((resolve, reject) => {
            try {
                const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
                const url = `${protocol}//${this.address}:${this.port}`;
                this.socket = new WebSocket(url);

                this.socket.onopen = () => {
                    resolve();
                };

                this.socket.onmessage = (event) => {
                    this.messageBuffer += event.data;
                    const messages = this.messageBuffer.split('\n');
                    this.messageBuffer = messages.pop() || '';

                    for (const msg of messages) {
                        if (msg.trim()) {
                            const handler = this.messageQueue.shift();
                            if (handler) {
                                if (msg === 'Fail') {
                                    handler.reject(
                                        new RequestError(
                                            `Request failed: ${this.lastSent.trim()}`
                                        )
                                    );
                                } else {
                                    handler.resolve(msg);
                                }
                            }
                        }
                    }
                };

                this.socket.onerror = (error) => {
                    reject(new Error(`WebSocket error: ${error}`));
                };

                this.socket.onclose = () => {
                    this.socket = null;
                };
            } catch (error) {
                reject(error);
            }
        });
    }

    /**
     * Disconnect from the server
     */
    disconnect(): void {
        if (this.socket) {
            this.socket.close();
            this.socket = null;
        }
    }

    /**
     * Send a command
     */
    send(fn: string, ...data: any[]): void {
        if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
            throw new Error('WebSocket is not connected');
        }
        const message = `${fn}(${flattenParameters(data)})\n`;
        this.lastSent = message;
        this.socket.send(message);
    }

    /**
     * Receive a response
     */
    private receive(): Promise<string> {
        return new Promise((resolve, reject) => {
            this.messageQueue.push({ resolve, reject });
        });
    }

    /**
     * Send a command and receive a response
     */
    async sendReceive(fn: string, ...data: any[]): Promise<string> {
        this.send(fn, ...data);
        return this.receive();
    }

    /**
     * Drain incoming data
     */
    drain(): void {
        // WebSocket doesn't have the same drain concept as socket.select
        // but we can clear the message queue
        this.messageQueue = [];
    }
}

/**
 * Minecraft API connection handler
 */
export class CmdPositioner {
    protected conn: Connection;
    protected pkg: string;

    constructor(conn: Connection, pkg: string) {
        this.conn = conn;
        this.pkg = pkg;
    }

    /**
     * Get entity position
     */
    async getPos(id: number = 0): Promise<Vec3> {
        const response = await this.conn.sendReceive(`${this.pkg}.getPos`, id);
        const [x, y, z] = response.split(',').map(parseFloat);
        return new Vec3(x, y, z);
    }

    /**
     * Set entity position
     */
    async setPos(id: number, x: number, y: number, z: number): Promise<void> {
        await this.conn.sendReceive(`${this.pkg}.setPos`, id, x, y, z);
    }

    /**
     * Get tile position
     */
    async getTilePos(id: number = 0): Promise<Vec3> {
        const response = await this.conn.sendReceive(`${this.pkg}.getTile`, id);
        const [x, y, z] = response.split(',').map(parseInt);
        return new Vec3(x, y, z);
    }

    /**
     * Set tile position
     */
    async setTilePos(id: number, x: number, y: number, z: number): Promise<void> {
        await this.conn.sendReceive(
            `${this.pkg}.setTile`,
            id,
            Math.floor(x),
            Math.floor(y),
            Math.floor(z)
        );
    }

    /**
     * Set a player setting
     */
    async setting(setting: string, status: boolean): Promise<void> {
        await this.conn.sendReceive(`${this.pkg}.setting`, setting, status ? 1 : 0);
    }
}

/**
 * Entity commands
 */
export class CmdEntity extends CmdPositioner {
    constructor(conn: Connection) {
        super(conn, 'entity');
    }
}

/**
 * Player commands
 */
export class CmdPlayer extends CmdPositioner {
    constructor(conn: Connection) {
        super(conn, 'player');
    }

    async getPos(): Promise<Vec3> {
        return super.getPos(0);
    }

    async setPos(x: number, y: number, z: number): Promise<void> {
        return super.setPos(0, x, y, z);
    }

    async getTilePos(): Promise<Vec3> {
        return super.getTilePos(0);
    }

    async setTilePos(x: number, y: number, z: number): Promise<void> {
        return super.setTilePos(0, x, y, z);
    }
}

/**
 * Camera commands
 */
export class CmdCamera {
    private conn: Connection;

    constructor(conn: Connection) {
        this.conn = conn;
    }

    async setNormal(entityId?: number): Promise<void> {
        await this.conn.sendReceive('camera.mode.setNormal', entityId ?? []);
    }

    async setFixed(): Promise<void> {
        await this.conn.sendReceive('camera.mode.setFixed');
    }

    async setFollow(entityId?: number): Promise<void> {
        await this.conn.sendReceive('camera.mode.setFollow', entityId ?? []);
    }

    async setPos(x: number, y: number, z: number): Promise<void> {
        await this.conn.sendReceive('camera.setPos', x, y, z);
    }
}

/**
 * Block events
 */
export class CmdEvents {
    private conn: Connection;

    constructor(conn: Connection) {
        this.conn = conn;
    }

    async clearAll(): Promise<void> {
        await this.conn.sendReceive('events.clearAll');
    }

    async blockHits(): Promise<BlockEvent[]> {
        const response = await this.conn.sendReceive('events.block.hits');
        const events: BlockEvent[] = [];

        if (response.trim()) {
            const lines = response.split('|');
            for (const line of lines) {
                const parts = line.split(',');
                if (parts.length === 5) {
                    events.push(
                        BlockEvent.hit(
                            parseFloat(parts[0]),
                            parseFloat(parts[1]),
                            parseFloat(parts[2]),
                            parseInt(parts[3]),
                            parseInt(parts[4])
                        )
                    );
                }
            }
        }

        return events;
    }
}

/**
 * Main Minecraft API class
 */
export class Minecraft {
    public player: CmdPlayer;
    public entity: CmdEntity;
    public camera: CmdCamera;
    public events: CmdEvents;

    private conn: Connection;

    constructor(conn: Connection) {
        this.conn = conn;
        this.player = new CmdPlayer(conn);
        this.entity = new CmdEntity(conn);
        this.camera = new CmdCamera(conn);
        this.events = new CmdEvents(conn);
    }

    /**
     * Connect to the Minecraft server
     */
    async connect(): Promise<void> {
        await this.conn.connect();
    }

    /**
     * Disconnect from the server
     */
    disconnect(): void {
        this.conn.disconnect();
    }

    /**
     * Post a message to the game chat
     */
    async postToChat(message: string): Promise<void> {
        await this.conn.sendReceive('chat.post', message);
    }

    /**
     * Set a block
     */
    async setBlock(x: number, y: number, z: number, block: Block): Promise<void> {
        await this.conn.sendReceive('world.setBlock', x, y, z, block.id, block.data);
    }

    /**
     * Get a block
     */
    async getBlock(x: number, y: number, z: number): Promise<Block> {
        const response = await this.conn.sendReceive('world.getBlock', x, y, z);
        const [id, data] = response.split(',').map(parseInt);
        return new Block(id, data);
    }

    /**
     * Set multiple blocks
     */
    async setBlocks(
        x1: number,
        y1: number,
        z1: number,
        x2: number,
        y2: number,
        z2: number,
        block: Block
    ): Promise<void> {
        await this.conn.sendReceive(
            'world.setBlocks',
            x1,
            y1,
            z1,
            x2,
            y2,
            z2,
            block.id,
            block.data
        );
    }
}

/**
 * Flatten parameters for sending to server
 */
function flattenParameters(data: any[]): string {
    const flattened: any[] = [];

    function flatten(item: any): void {
        if (Array.isArray(item) && typeof item !== 'string') {
            for (const element of item) {
                flatten(element);
            }
        } else if (item instanceof Block) {
            flattened.push(item.id, item.data);
        } else if (item instanceof Vec3) {
            flattened.push(item.x, item.y, item.z);
        } else if (item !== undefined && item !== null) {
            flattened.push(item);
        }
    }

    flatten(data);
    return flattened.map((v) => String(v)).join(',');
}

// Standard block definitions
export const Blocks = {
    AIR: new Block(0),
    STONE: new Block(1),
    GRASS: new Block(2),
    DIRT: new Block(3),
    COBBLESTONE: new Block(4),
    WOOD_PLANKS: new Block(5),
    SAPLING: new Block(6),
    BEDROCK: new Block(7),
    WATER_FLOWING: new Block(8),
    WATER: new Block(8),
    WATER_STATIONARY: new Block(9),
    LAVA_FLOWING: new Block(10),
    LAVA: new Block(10),
    LAVA_STATIONARY: new Block(11),
    SAND: new Block(12),
    GRAVEL: new Block(13),
    GOLD_ORE: new Block(14),
    IRON_ORE: new Block(15),
    COAL_ORE: new Block(16),
    WOOD: new Block(17),
    LEAVES: new Block(18),
    GLASS: new Block(20),
    LAPIS_LAZULI_ORE: new Block(21),
    LAPIS_LAZULI_BLOCK: new Block(22),
    SANDSTONE: new Block(24),
    BED: new Block(26),
    COBWEB: new Block(30),
    GRASS_TALL: new Block(31),
    WOOL: new Block(35),
    FLOWER_YELLOW: new Block(37),
    FLOWER_CYAN: new Block(38),
    MUSHROOM_BROWN: new Block(39),
    MUSHROOM_RED: new Block(40),
    GOLD_BLOCK: new Block(41),
    IRON_BLOCK: new Block(42),
    STONE_SLAB_DOUBLE: new Block(43),
    STONE_SLAB: new Block(44),
    BRICK_BLOCK: new Block(45),
    TNT: new Block(46),
    BOOKSHELF: new Block(47),
    MOSS_STONE: new Block(48),
    OBSIDIAN: new Block(49),
    TORCH: new Block(50),
    FIRE: new Block(51),
    STAIRS_WOOD: new Block(53),
    CHEST: new Block(54),
    DIAMOND_ORE: new Block(56),
    DIAMOND_BLOCK: new Block(57),
    CRAFTING_TABLE: new Block(58),
    FARMLAND: new Block(60),
    FURNACE_INACTIVE: new Block(61),
    FURNACE_ACTIVE: new Block(62),
    DOOR_WOOD: new Block(64),
    LADDER: new Block(65),
    STAIRS_COBBLESTONE: new Block(67),
    DOOR_IRON: new Block(71),
    REDSTONE_ORE: new Block(73),
    SNOW: new Block(78),
    ICE: new Block(79),
    SNOW_BLOCK: new Block(80),
    CACTUS: new Block(81),
    CLAY: new Block(82),
    SUGAR_CANE: new Block(83),
    FENCE: new Block(85),
    GLOWSTONE_BLOCK: new Block(89),
    BEDROCK_INVISIBLE: new Block(95),
    STONE_BRICK: new Block(98),
    GLASS_PANE: new Block(102),
    MELON: new Block(103),
    FENCE_GATE: new Block(107),
    GLOWING_OBSIDIAN: new Block(246),
    NETHER_REACTOR_CORE: new Block(247),
};

/**
 * Create a connection and return Minecraft API instance
 */
export async function createMinecraft(
    address: string = 'localhost',
    port: number = 4711
): Promise<Minecraft> {
    const conn = new Connection(address, port);
    await conn.connect();
    return new Minecraft(conn);
}
