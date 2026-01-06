# 🚀 Render Deployment Guide (Backend)

This guide explains how to deploy your Node.js/MongoDB backend to **Render**.

## 1. Prepare your MongoDB Database (Atlas)
Since Render doesn't provide a database, you should use **MongoDB Atlas** (Free Tier):
1.  Go to [MongoDB Atlas](https://www.mongodb.com/cloud/atlas) and create a free account.
2.  Create a new Cluster (pick the region closest to you).
3.  Go to **Database Access** and create a user (remember the password).
4.  Go to **Network Access** and select "Allow Access from Anywhere" (Render's IPs change frequently).
5.  Go to **Database** -> **Connect** -> **Connect your application**.
6.  Copy the connection string (it looks like `mongodb+srv://<username>:<password>@cluster0.abc.mongodb.net/?retryWrites=true&w=majority`).

## 2. Push Code to GitHub
We have already pushed the latest code to the `MongoDB` branch. Ensure you are pushing to the same repository you link to Render.

## 3. Create a Web Service on Render
1.  Log in to [Render.com](https://render.com/).
2.  Click **New +** -> **Web Service**.
3.  Connect your GitHub repository.
4.  Configure the service:
    *   **Name**: `smart-parcel-api`
    *   **Environment**: `Node`
    *   **Region**: (Same as your MongoDB Cluster)
    *   **Branch**: `MongoDB`
    *   **Root Directory**: `server` 👈 **IMPORTANT!** (Because your backend is in a subfolder)
    *   **Build Command**: `npm install`
    *   **Start Command**: `node src/app.js` (or `npm start`)

## 4. Set Environment Variables
In the Render dashboard, go to the **Environment** tab and add:
*   `NODE_ENV`: `production`
*   `MONGODB_URI`: (Your string from Step 1)
*   `JWT_SECRET`: (A long random string, e.g., `your_very_secret_key_12345`)
*   `PORT`: `5000` (Render will override this, but it's good for defaults)

## 5. Deployment
*   Render will start building and deploying automatically.
*   Once finished, you will get a URL like `https://smart-parcel-api.onrender.com`.

## 6. Update Flutter App
Once deployed, you need to update your API base URL in the Flutter app to point to your new Render URL instead of `localhost`.

---

### ⚠️ Note on WebSockets
Render's free tier "spins down" after 15 minutes of inactivity. When it spins down, the ESP32 and App will lose connection. To prevent this, you'd need the "Starter" plan ($7/mo) or use a ping service to keep it awake.
