import {request} from './moonshacl.mjs';

// The engine is synchronous; isolate it from painting, keyboard and screen-reader updates.
self.addEventListener('message', ({data}) => {
  try {
    const result = JSON.parse(request(JSON.stringify(data.payload)));
    self.postMessage({id: data.id, result});
  } catch (error) {
    self.postMessage({id: data.id, error: error instanceof Error ? error.message : String(error)});
  }
});
self.postMessage({ready: true});
