const mongose = require('mongoose');

const MONGO_URI = process.env.MONGO_URI;

const connectDb = async() =>{
    try{
        const conn = await mongose.connect(MONGO_URI);

        console.log(`MongoDb coneected: ${conn.connection.host}`);
    } catch(error){
        console.error(`error connecting to mongoDb: ${error.message}`);
        process.exit(1);
    }
};

module.exports = connectDb;