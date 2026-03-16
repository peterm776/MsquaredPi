use wasm_bindgen::prelude::*;
use serde::{Serialize, Deserialize};

/// Vector3 representation for coordinates
#[wasm_bindgen]
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub struct Vec3 {
    pub x: f64,
    pub y: f64,
    pub z: f64,
}

#[wasm_bindgen]
impl Vec3 {
    #[wasm_bindgen(constructor)]
    pub fn new(x: f64, y: f64, z: f64) -> Vec3 {
        Vec3 { x, y, z }
    }

    pub fn length(&self) -> f64 {
        self.length_squared().sqrt()
    }

    pub fn length_squared(&self) -> f64 {
        self.x * self.x + self.y * self.y + self.z * self.z
    }

    pub fn add(&self, other: &Vec3) -> Vec3 {
        Vec3 {
            x: self.x + other.x,
            y: self.y + other.y,
            z: self.z + other.z,
        }
    }

    pub fn subtract(&self, other: &Vec3) -> Vec3 {
        Vec3 {
            x: self.x - other.x,
            y: self.y - other.y,
            z: self.z - other.z,
        }
    }

    pub fn multiply(&self, scalar: f64) -> Vec3 {
        Vec3 {
            x: self.x * scalar,
            y: self.y * scalar,
            z: self.z * scalar,
        }
    }

    pub fn clone(&self) -> Vec3 {
        Vec3 {
            x: self.x,
            y: self.y,
            z: self.z,
        }
    }

    pub fn to_string(&self) -> String {
        format!("Vec3({},{},{})", self.x, self.y, self.z)
    }
}

/// Block representation
#[wasm_bindgen]
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub struct Block {
    pub id: u32,
    pub data: u32,
}

#[wasm_bindgen]
impl Block {
    #[wasm_bindgen(constructor)]
    pub fn new(id: u32, data: u32) -> Block {
        Block { id, data }
    }

    pub fn with_data(&self, data: u32) -> Block {
        Block {
            id: self.id,
            data,
        }
    }

    pub fn to_string(&self) -> String {
        format!("Block({}, {})", self.id, self.data)
    }
}

/// Block event (hit, placed, removed, etc.)
#[wasm_bindgen]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlockEvent {
    pub event_type: u32,
    pub pos: Vec3,
    pub face: u32,
    pub entity_id: i32,
}

#[wasm_bindgen]
impl BlockEvent {
    pub const HIT: u32 = 0;

    #[wasm_bindgen(constructor)]
    pub fn new(event_type: u32, x: f64, y: f64, z: f64, face: u32, entity_id: i32) -> BlockEvent {
        BlockEvent {
            event_type,
            pos: Vec3::new(x, y, z),
            face,
            entity_id,
        }
    }

    pub fn hit(x: f64, y: f64, z: f64, face: u32, entity_id: i32) -> BlockEvent {
        BlockEvent::new(BlockEvent::HIT, x, y, z, face, entity_id)
    }

    pub fn to_string(&self) -> String {
        format!(
            "BlockEvent({}, {}, {}, {}, {}, {})",
            self.event_type, self.pos.x, self.pos.y, self.pos.z, self.face, self.entity_id
        )
    }
}

/// Result type for operations
pub type Result<T> = std::result::Result<T, String>;

/// Error types
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("Connection error: {0}")]
    ConnectionError(String),
    
    #[error("Request failed: {0}")]
    RequestFailed(String),
    
    #[error("Parse error: {0}")]
    ParseError(String),
}

impl From<Error> for JsValue {
    fn from(err: Error) -> JsValue {
        JsValue::from_str(&err.to_string())
    }
}
